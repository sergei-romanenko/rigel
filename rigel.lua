local IR = require("ir")
local types = require("types")
--local ffi = require("ffi")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err
local SDF = require("sdf")

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

local darkroom = {}

-- enable SDF checking? (true:enable, false:disable)
darkroom.SDF = true
darkroom.default_nettype_none = true

-- path to root of rigel repo
darkroom.path = string.sub(debug.getinfo(1).source,2,#debug.getinfo(1).source-9)

DEFAULT_FIFO_SIZE = 2048*16*16

if os.getenv("v") then
  DARKROOM_VERBOSE = true
else
  DARKROOM_VERBOSE = false
end

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline.."\n"..debug.traceback()
end

local AddressMT = {}
function darkroom.Address(num)
  assert(type(num)=="number")
  return setmetatable({num},AddressMT)
end

darkroom.VTrigger = types.VTrigger
darkroom.RVTrigger = types.RVTrigger
darkroom.HandshakeTrigger = types.HandshakeTrigger
darkroom.V = types.V
darkroom.RV = types.RV
darkroom.Handshake = types.Handshake
darkroom.HandshakeArray = types.HandshakeArray
darkroom.HandshakeTriggerArray = types.HandshakeTriggerArray
darkroom.HandshakeTuple = types.HandshakeTuple
darkroom.HandshakeArrayOneHot = types.HandshakeArrayOneHot
darkroom.HandshakeTmuxed = types.HandshakeTmuxed
darkroom.isHandshakeArrayOneHot = types.isHandshakeArrayOneHot
darkroom.isHandshakeTmuxed = types.isHandshakeTmuxed
darkroom.isHandshake = types.isHandshake
darkroom.isHandshakeTrigger = types.isHandshakeTrigger
darkroom.isHandshakeArray = types.isHandshakeArray
darkroom.isHandshakeTriggerArray = types.isHandshakeTriggerArray
darkroom.isHandshakeTuple = types.isHandshakeTuple
darkroom.isHandshakeAny = types.isHandshakeAny
darkroom.isV = types.isV
darkroom.isVTrigger = types.isVTrigger
darkroom.isRV = types.isRV
darkroom.isRVTrigger = types.isRVTrigger
darkroom.expectBasic = types.expectBasic
darkroom.expectV = types.expectV
darkroom.expectRV = types.expectRV
darkroom.expectHandshake = types.expectHandshake
darkroom.lower = types.lower
darkroom.extractData = types.extractData
darkroom.hasReady = types.hasReady
darkroom.extractReady = types.extractReady
darkroom.extractValid = types.extractValid
darkroom.streamCount = types.streamCount
darkroom.isStreaming = types.isStreaming
darkroom.isBasic = types.isBasic

local function discoverName(x)
  local y = 1
  while true do
    local name, value = debug.getlocal(3,y)
    if not name then break end
    --print(name,value)

    if value==x then
      return name
    end
    
    y = y + 1
  end

  for k,v in pairs(_G) do
    if v==x then
      --print("FOUND_G")
      return k
    end
  end
--  return {input=x}    
end

darkroom.__unnamedID = 0

local function typeToKey(t)
  local res = {}

  local Uniform = require "uniform"
  
  for k,v in pairs(t) do
    if type(k)=="number" then
      local outk
      
      if type(v)=="number" then
        outk="number"
      elseif type(v)=="boolean" then
        outk="bool"
      elseif type(v)=="string" then
        outk="string"
      elseif type(v)=="function" then
        outk="luaFunction"
      elseif types.isType(v) then
        outk="type"
      elseif darkroom.isFunction(v) then
        outk="rigelFunction"
      elseif SDF.isSDF(v) then
        outk="rate"
      elseif type(v)=="table" and getmetatable(v)==AddressMT then
        outk="address"
        v=v[1]
      elseif type(v)=="table" and J.keycount(v)==2 and #v==2 and type(v[1])=="number" and type(v[2])=="number" then
        outk="size"
      elseif type(v)=="table" and J.keycount(v)==4 and #v==4 and type(v[1])=="number" and type(v[2])=="number"
             and type(v[3])=="number" and type(v[4])=="number" then
        outk="bounds"
      elseif Uniform.isUniform(v) then
        if v:isNumber() then
          outk="number"
          if v.kind=="const" then
            v = v:toNumber()
          else
	    
          end
        else
          J.err("NYI - typeToKey "..tostring(v))
        end
      elseif type(v)=="table" and #t==J.keycount(t) and J.foldl(J.andop,false,J.map(v,darkroom.isInstance)) then
        outk="instanceList"
      else
        J.err(false,"unknown type to key? "..tostring(v))
      end
      
      J.err( res[outk]==nil, "Generator key '"..outk.."' is set twice?" )
      res[outk] = v
    else
      J.err( res[k]==nil, "Generator key '"..k.."' is set twice?" )
      res[k] = v
    end
  end
  return res
end

local functionGeneratorFunctions = {}
local functionGeneratorMT={}

functionGeneratorMT.__call=function(tab,...)
  local rawarg = {...}

  if darkroom.isIR(rawarg[1]) then
    local arg
    if #rawarg>1 and rawarg[1].type:is("HandshakeTrigger") then
      -- sort of a hack: handshake trigger can only be made into arrays
      arg = darkroom.concatArray2d(nil,rawarg,#rawarg)
    elseif #rawarg>1 then
      -- collapse multi args into tuple
      arg = darkroom.concat(nil, rawarg)
    else
      arg = rawarg[1]
    end
    
    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    if arglist.type==nil then arglist.type = arg.type end
    if arglist.rate==nil then arglist.rate = arg.rate end
    return tab:complete(arglist)(arg)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling a function generator with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    for k,v in pairs(arg) do
      J.err( arglist[k]==nil, "Argument '"..k.."' was already passed to function generator '"..tab.name.."'" )
      arglist[k] = v
    end
    
    if tab:checkArgs(arglist) then
      return tab:complete(arglist)
    else
      -- not done yet, return curried generator
      local res = darkroom.newFunctionGenerator( tab.namespace, tab.name, tab.requiredArgs, tab.optArgs, tab.completeFn )
      res.curriedArgs = arglist
      return res
    end
  else
    J.err(false, "Called function generator '"..tab.name.."' with something other than a Rigel value or table ("..tostring(rawarg[1])..")? Make sure you call function generator with curly brackets {}")
  end
end
functionGeneratorMT.__tostring=function(tab)
  local res = {}
  table.insert(res,"Function Generator "..tab.namespace.."."..tab.name)
  table.insert(res,"  Required Args:")
  for k,v in pairs(tab.requiredArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Curried Args:")
  for k,v in pairs(tab.curriedArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Optional Args:")
  for k,v in pairs(tab.optArgs) do table.insert(res,"    "..k) end
  return table.concat(res,"\n")
end
functionGeneratorMT.__index = functionGeneratorFunctions


-- return true if done, false if not done
function functionGeneratorFunctions:checkArgs(arglist)
  local reqArgs = {}

  for k,v in pairs(arglist) do
    if self.requiredArgs[k]==nil and self.optArgs[k]==nil then
      print("Error, arg '"..k.."' is not in list of required or optional args on function generator '"..self.namespace.."."..self.name.."'!" )
      print("Required Args: ")
      for k,v in pairs(self.requiredArgs) do print(k..",") end
      assert(false)
    end
    if self.requiredArgs[k]~=nil then reqArgs[k]=1 end
  end

  return J.keycount(reqArgs)==J.keycount(self.requiredArgs)
end

function functionGeneratorFunctions:listRequiredArgs()
  local s = {}
  for k,v in pairs(self.requiredArgs) do if self.curriedArgs[k]==nil then table.insert(s,k) end end
  return table.concat(s,",")
end

-- does this generate require the arg 'arg'? (returns true if either required or optional)
function functionGeneratorFunctions:requiresArg(arg)
  assert(type(arg)=="string")
  return (self.requiredArgs[arg]~=nil or self.optArgs[arg]~=nil) and (self.curriedArgs[arg]==nil)
end

function functionGeneratorFunctions:complete(arglist)
  if self:checkArgs(arglist)==false then
    print("Function generator '"..self.name.."' is missing arguments!")
    for k,v in pairs(self.requiredArgs) do
      if self.curriedArgs[k]==nil then print("Requires argument '"..k.."'") end
    end
    assert(false)
  end
  local mod = self.completeFn(arglist)
  J.err( darkroom.isPlainFunction(mod), "function generator '"..self.namespace.."."..self.name.."' returned something other than a rigel function? "..tostring(mod) )
  mod.generator = self
  mod.generatorArgs = arglist
  return mod
end

function darkroom.newFunctionGenerator( namespace, name, requiredArgs, optArgs, completeFn )
  err( type(namespace)=="string", "newFunctionGenerator: namespace must be string" )
  err( type(name)=="string", "newFunctionGenerator: name must be table" )
  err( type(requiredArgs)=="table", "newFunctionGenerator: requiredArgs must be table" )
  if J.keycount(requiredArgs)==#requiredArgs then requiredArgs = J.invertTable(requiredArgs) end -- convert array of names to set
  for k,v in pairs(requiredArgs) do J.err( type(k)=="string", "newFunctionGenerator: requiredArgs must be set of strings" ) end
  err( type(optArgs)=="table", "newFunctionGenerator: requiredArgs must be table" )
  if J.keycount(optArgs)==#optArgs then optArgs = J.invertTable(optArgs) end -- convert array of names to set
  for k,v in pairs(optArgs) do J.err( type(k)=="string", "newFunctionGenerator: optArgs must be set of strings" ) end
  err( type(completeFn)=="function", "newFunctionGenerator: completeFn must be lua function" )
  
  return setmetatable( {namespace=namespace, name=name, requiredArgs=requiredArgs, optArgs=optArgs, completeFn=completeFn, curriedArgs={} }, functionGeneratorMT )
end
function darkroom.isFunctionGenerator(t) return (getmetatable(t)==functionGeneratorMT) or darkroom.isModuleGeneratorInstanceCallsite(t) end

local function buildAndCheckSystolicModule(tab, isModule)
  -- build the systolic module as needed
  err( rawget(tab, "makeSystolic")~=nil, "missing makeSystolic() for "..J.sel(isModule,"module","function").." '"..tab.name.."'" )
  local sm = rawget(tab,"makeSystolic")()
  if Ssugar.isModuleConstructor(sm) then sm:complete(); sm=sm.module end
  J.err( S.isModule(sm),"makeSystolic didn't return a systolic module? Returned '"..tostring(sm).."'. Module: "..tostring(tab))

  local systolicFns = sm.functions
  local rigelFns = tab.functions
  if isModule==false then
    systolicFns={["process"]=sm.functions.process}
    rigelFns = {["process"]=tab}
  end

  --err( J.keycount(systolicFns)==J.keycount(rigelFns),"systolic module and rigel module fn lists don't match? module '"..tab.name.."' systolic: "..table.concat(J.invertAndStripKeys(systolicFns),",").." rigel: "..table.concat(J.invertAndStripKeys(rigelFns),","))
  
  for fnname,rigelFn in pairs(rigelFns) do
    local systolicFn = systolicFns[fnname]

    err( systolicFn~=nil, "systolic module function is missing ("..tostring(sm.name)..")")
    
    if rigelFn.outputType~=types.null() then
      err( systolicFn.output~=nil, "module output is not null (is "..tostring(rigelFn.outputType).."), but systolic output is missing")
      err( darkroom.lower(rigelFn.outputType)==systolicFn.output.type, "module output type wrong on module '"..tab.name.."'? is '"..tostring(systolicFn.output.type).."' but should be '"..tostring(darkroom.lower(rigelFn.outputType)).."'" )
    end
    
    if types.isHandshakeAny(rigelFn.inputType) or types.isHandshakeAny(rigelFn.outputType) then
      local readyName = fnname.."_ready"
      if isModule==false then readyName="ready" end
      
      err( sm.functions[readyName]~=nil, "module ready function missing?")

      if rigelFn.inputType~=types.null() and darkroom.extractReady(rigelFn.inputType)~=sm.functions[readyName].output.type then
        err(false, "module '"..tab.name.."' systolic ready output type wrong. Systolic ready output type is '"..tostring(sm.functions[readyName].output.type).."', but should be '"..tostring(darkroom.extractReady(rigelFn.inputType)).."', because Rigel function input type is '"..tostring(rigelFn.inputType).."'.")
      end

      if types.isHandshakeAny(rigelFn.inputType)==false and sm.functions[readyName].output~=nil then
        err(sm.functions[readyName].output.type==types.null(),"Systolic module '"..tab.name.."' function '"..readyName.."' (input type "..tostring(rigelFn.inputType)..") shouldn't return anything, but returns type: "..tostring(sm.functions[readyName].output.type))
      end
      
    end


    err( darkroom.lower(rigelFn.inputType)==systolicFn.inputParameter.type, "module input type wrong?" )
    
  end

  err( (sm.functions.reset~=nil)==tab.stateful, "Modules must have reset iff the module is stateful (module "..tab.name.."). stateful:"..tostring(tab.stateful).." hasReset:"..tostring(sm.functions.reset~=nil))
  
  for inst,lst in pairs(sm.externalInstances) do
    for _,fnname in ipairs(lst) do
      local found = false

      for ic,_ in pairs(tab.requires) do if ic.instance.name==inst.name and ic.functionName==fnname then found=true end end
      for ic,_ in pairs(tab.provides) do if ic.instance.name==inst.name and ic.functionName==fnname then found=true end end
      err( found, "makeSystolic(): systolic module '"..sm.name.."' refers to external instance '"..inst.name.."', but rigel module doesn't?")
    end
  end

  for inst,fnmap in pairs(tab.requires) do
    err( sm.externalInstances[inst:toSystolicInstance()]~=nil, "Rigel module '"..tab.name.."' requires instance '"..inst.name.."', but it's missing from systolic module external list? ")
    for fnname,_ in pairs(fnmap) do
      err( sm.externalInstances[inst:toSystolicInstance()][fnname]~=nil, "Rigel module requires instance, but it's missing from systolic module? ")

      local fn = inst.module.functions[fnname]
      if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
        err( sm.externalInstances[inst:toSystolicInstance()][fnname.."_ready"]~=nil, "Rigel module '"..tab.name.."' requires instance callsite '"..inst.name..":"..fnname.."()', but its ready fn is missing from systolic module external list? ")
      end
    end
  end
  
  rawset(tab,"systolicModule", sm )
  return sm
end

function buildAndCheckTerraModule(tab)
  err( rawget(tab, "makeTerra")~=nil, "missing terraModule, and 'makeTerra' doesn't exist on module '"..tab.name.."'" )
  err( type(rawget(tab, "makeTerra"))=="function", "'makeTerra' function not a lua function, but is "..tostring(rawget(tab, "makeTerra")) )
  local tm = rawget(tab,"makeTerra")()
  err( terralib.types.istype(tm) and tm:isstruct(), "makeTerra for module '"..tab.name.."' returned something other than a terra struct? returned: "..tostring(tm))
  
  rawset(tab,"terraModule", tm )
  return tm
end

local darkroomFunctionFunctions = {}
local darkroomFunctionMT = {
__index=function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = darkroomFunctionFunctions[key]
  if v~=nil then return v end

  if key=="systolicModule" then
    return buildAndCheckSystolicModule(tab,false)
  elseif key=="terraModule" then
    return buildAndCheckTerraModule(tab)
  end
end,
__call=function(tab,...)
  local rawarg = {...}

  for _,arg in pairs(rawarg) do
    J.err( arg==nil or darkroom.isIR(arg),"Input argument to rigel function '"..tab.name.."' must be a rigel value, but is:'"..tostring(arg).."'")

    -- discover variable name from lua
    if arg~=nil and arg.defaultName then
      local n = discoverName(arg)
      if n~=nil then
        arg.name=n.."_"..darkroom.__unnamedID
        darkroom.__unnamedID = darkroom.__unnamedID+1
        arg.defaultname=false
      end
    end
  end

  local arg
  if #rawarg>1 and rawarg[1].type:is("HandshakeTrigger") then
    -- sort of a hack: handshake trigger can only be made into arrays
    arg = darkroom.concatArray2d(nil,rawarg,#rawarg)
  elseif #rawarg>1 then
    arg = darkroom.concat(nil,rawarg)
  else
    arg = rawarg[1]
  end
  
  local res = darkroom.apply("un"..darkroom.__unnamedID.."_"..tab.name:sub(1,20), tab, arg)
  res.defaultName=true
  darkroom.__unnamedID = darkroom.__unnamedID+1
  return res
end,
__tostring=function(mod)
  local res = {}

  local mt = getmetatable(mod)
  setmetatable(mod,nil)
  local tabstr = tostring(mod)
  setmetatable(mod,mt)

  table.insert(res,"Rigel Function "..mod.name.." ("..tabstr..")")
  table.insert(res,"  InputType: "..tostring(mod.inputType))
  table.insert(res,"  OutputType: "..tostring(mod.outputType))

  if SDFRate.isSDFRate(mod.sdfInput) then
    table.insert(res,"  InputSDF: "..tostring(mod.sdfInput))
  else
    table.insert(res,"  InputSDF: Not an SDF rate?")
  end

  if SDFRate.isSDFRate(mod.sdfOutput) then
    table.insert(res,"  OutputSDF: "..tostring(mod.sdfOutput))
  else
    table.insert(res,"  OutputSDF: Not an SDF rate?")
  end

  table.insert(res,"  Stateful: "..tostring(mod.stateful))
    
  table.insert(res,"  Metadata:")
  for k,v in pairs(mod.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end

  if J.keycount(mod.requires)>0 then
    table.insert(res,"  Requires:")
    for inst,fnlist in pairs(mod.requires) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Requires: (none)")
  end

  if J.keycount(mod.provides)>0 then
    table.insert(res,"  Provides:")
    for inst,fnlist in pairs(mod.provides) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Provides: (none)")
  end

  if mod.kind=="lambda" then
    if J.keycount(mod.instanceMap)==0 then
      table.insert(res,"  Internal Instances: (none)")
    else
      table.insert(res,"  Internal Instances:")
      for inst,_ in pairs(mod.instanceMap) do
        table.insert(res,"    "..inst.name..":"..inst.module.name)
      end
    end

    mod.output:visitEach(function(n) table.insert(res,tostring(n)) end)
  end
  
  return table.concat(res,"\n").."\n"
end
}


-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( Isdf, loc )
  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: first argument index 1 should be SDF rate" )
  err( type(loc)=="string", "sdfTransfer: loc should be string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( SDFRate.isSDFRate(self.sdfInput), "Missing SDF rate for fn "..self.name..". is: "..tostring(self.sdfInput))
  err( SDFRate.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn "..self.name)

  local consistantRatio = true

  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: input argument should be SDF rate" )
  err( #self.sdfInput == #Isdf, "# of SDF streams doesn't match. Was "..(#Isdf).." but expected "..(#self.sdfInput)..", "..loc )

  local Uniform = require "uniform"

  local ratio
  for i=1,#self.sdfInput do
    local thisR = { Isdf[i][1]*self.sdfInput[i][2], Isdf[i][2]*self.sdfInput[i][1] } -- I/self.sdfInput ratio
    --thisR[1],thisR[2] = J.simplify(thisR[1],thisR[2])
    if ratio==nil then
      ratio=thisR
    else
      consistantRatio = consistantRatio and ( (Uniform(ratio[1]*thisR[2])):eq(ratio[2]*thisR[1]):assertAlwaysTrue() )
    end
  end

  err( consistantRatio, "SDFTransfer: ratio is not consistant, Input rate: "..tostring(Isdf).." module rate: "..tostring(self.sdfInput) )
  
  local res = {}
  for i=1,#self.sdfOutput do
    --local On, Od = J.simplify(self.sdfOutput[i][1]*ratio[1], self.sdfOutput[i][2]*ratio[2])
    local On, Od = self.sdfOutput[i][1]*ratio[1], self.sdfOutput[i][2]*ratio[2]
    table.insert( res, {On,Od} )
  end

  assert( SDFRate.isSDFRate(res) )

  return res
end

function darkroomFunctionFunctions:toTerra() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() 
  local ntn = ""
  if darkroom.default_nettype_none then
    ntn = [[`default_nettype none // enable extra sanity checking
]]
  end
  return ntn..self.systolicModule:getDependencies()..self.systolicModule:toVerilog() 
end

function darkroomFunctionFunctions:toVerilogNoHeader()
  return self.systolicModule:toVerilogNoHeader()
end

function darkroomFunctionFunctions:vHeaderInOut(fnname)
  if fnname==nil then fnname="process" end
  assert(type(fnname)=="string")
  
  local v = {"\n/* function "..fnname.."*/\n"}
  if self.inputType==types.null() then
  elseif types.isHandshakeAny(self.inputType) then
    local readyName = "ready"
    if fnname~="process" then readyName=fnname.."_ready" end
    table.insert(v,", input wire ["..(types.lower(self.inputType):verilogBits()-1)..":0] "..fnname.."_input, output wire ["..(types.extractReady(self.inputType):verilogBits()-1)..":0] "..readyName)
  elseif types.isBasic(self.inputType) then
    table.insert(v,", input wire ["..(self.inputType:verilogBits()-1)..":0] "..fnname.."_input")

    if self.stateful or (self.delay~=nil and self.delay>0) then
      table.insert(v,", input wire CE, input wire "..fnname.."_valid")
    end
  else
    assert(false)
  end

  if self.outputType==types.null() then
  elseif types.isHandshakeAny(self.outputType) then
    local readyName = "ready_downstream"
    if fnname~="process" then readyName=fnname.."_ready_downstream" end
    
    table.insert(v,", output wire ["..(types.lower(self.outputType):verilogBits()-1)..":0] "..fnname.."_output, input wire ["..(types.extractReady(self.outputType):verilogBits()-1)..":0] "..readyName)
  elseif types.isBasic(self.outputType) then
    table.insert(v,", output wire ["..(self.outputType:verilogBits()-1)..":0] "..fnname.."_output")
  else
    assert(false)
  end

  return table.concat(v,"")
end

function darkroomFunctionFunctions:vHeaderRequires()
  local v = {}
  for inst,fnmap in pairs(self.requires) do
    for fnname,_ in pairs(fnmap) do
      local fn = inst.module.functions[fnname]

      --table.insert(v,"/* HEADER REQUIRES "..inst.name..":"..fnname.."*/")
      
      if types.isHandshakeAny(fn.inputType) then
        table.insert(v,", output wire ["..(types.lower(fn.inputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_input, input wire ["..(types.extractReady(fn.inputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_ready")
      elseif fn.inputType==types.null() then
      else
        print("NYI - require of: "..tostring(inst.name))
        assert(false)
      end
      
      if types.isHandshakeAny(fn.outputType) then
        table.insert(v,", input wire ["..(types.lower(fn.outputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_output, output wire "..inst.name.."_"..fnname.."_ready_downstream")
      elseif types.isBasic(fn.outputType) then
        table.insert(v,", input wire ["..(types.lower(fn.outputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_output")
      else
        print("NYI - require of: "..tostring(inst))
        assert(false)
      end
    end
  end

  return table.concat(v,"")
end

-- verilog header
function darkroomFunctionFunctions:vHeader()
  local v = {"module "..self.name.." (input wire CLK"}

  if self.stateful then
    table.insert(v, ", input wire reset")
  end

  table.insert(v,self:vHeaderInOut())
  table.insert(v,self:vHeaderRequires())
  
  
  assert(J.keycount(self.provides)==0)
  
  table.insert(v,[[);
parameter INSTANCE_NAME="INST";
]])
  return table.concat(v,"")
end

-- generate verilog code for set of instances
function darkroomFunctionFunctions:vInstances()
  local res = {}
  for inst,_ in pairs(self.instanceMap) do
    table.insert(res,inst:toVerilog())
  end
  return table.concat(res,"\n")
end

local darkroomModuleFunctions = {}

function darkroomModuleFunctions:vHeader()
    local v = {"module "..self.name.." (input wire CLK"}

  if self.stateful then
    table.insert(v, ", input wire reset")
  end

  for fnname,fn in pairs(self.functions) do
    table.insert(v,fn:vHeaderInOut(fnname))
  end

  table.insert(v,darkroomFunctionFunctions.vHeaderRequires(self))
  
  table.insert(v,[[);
parameter INSTANCE_NAME="INST";
]])
  return table.concat(v,"")
end

-- verilog value of input data (if handshaked)
function darkroomFunctionFunctions:vInputData()
  assert(types.isHandshakeAny(self.inputType))
  return "process_input["..(types.extractData(self.inputType):verilogBits()-1)..":0]"
end

-- verilog value of input valid (if handshaked)
function darkroomFunctionFunctions:vInputValid()
  assert(types.isHandshakeAny(self.inputType))
  return "process_input["..(types.lower(self.inputType):verilogBits()-1)..":"..types.extractData(self.inputType):verilogBits().."]"
end

-- verilog value of input ready (upstream ready) (if handshaked)
function darkroomFunctionFunctions:vInputReady()
  assert(types.isHandshakeAny(self.inputType))
  return "ready"
end

-- verilog value of output data (if handshaked)
function darkroomFunctionFunctions:vOutputData()
  assert(types.isHandshakeAny(self.outputType))
  return "process_output["..(types.extractData(self.outputType):verilogBits()-1)..":0]"
end

-- verilog value of output valid (if handshaked)
function darkroomFunctionFunctions:vOutputValid()
  assert(types.isHandshakeAny(self.outputType))
  return "process_output["..(types.lower(self.outputType):verilogBits()-1)..":"..types.extractData(self.outputType):verilogBits().."]"
end

-- verilog value of output ready (upstream ready) (if handshaked)
function darkroomFunctionFunctions:vOutputReady()
  assert(types.isHandshakeAny(self.outputType))
  return "ready_downstream"
end

function darkroomFunctionFunctions:instantiate(name,X)
  err( name==nil or type(name)=="string", "functon instantiate: input should be string")
  err( X==nil, "function instantiate: too many arguments" )
  
  if name==nil then
    name = "UnnamedFunctionInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiate(name, self )
  return res
end

darkroom.newInstanceCallsite = J.memoize(function( instance, functionName, X )
  err( darkroom.isInstance(instance),"newInstanceCallsite: instance should be instance" )
  err( type(functionName)=="string", "newInstanceCallsite: function name must be string, but is: "..tostring(functionName) )
  err( X==nil, "newInstanceCallsite: too many arguments" )

  err( darkroom.isPlainModule(instance.module), "newInstanceCallsite: instance should be plain module" )

  local fn = instance.module.functions[functionName]
  assert(fn~=nil)

  local G = require "generators"

  local res = G.Module{"InstCall_"..instance.name.."_"..functionName, fn.inputType, fn.sdfInput,
                       function(i)
                         local res = darkroom.applyMethod("callinstfn",instance,functionName,i)
                         return res
  end}
  res.stateful=false
  res.delay = fn.delay
  
  return res
end)
  
-- this function doesn't check that the function struct is valid, it only creates the data structure.
-- (ie that input type is correct, or that requires table is consistant).
function darkroom.newFunction(tab,X)
  err( type(tab) == "table", "rigel.newFunction: input must be table" )
  err( X==nil, "rigel.newFunction: too many arguments")
  err( getmetatable(tab)==nil,"rigel.newFunction: input table already has a metatable?")
  
  err( type(tab.name)=="string", "rigel.newFunction: name must be string, but is: "..tostring(tab.name) )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfInput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfOutput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or tab.sdfInput:allLE1(), "rigel.newFunction: sdf input rate is not <=1, but is: "..tostring(tab.sdfInput) )
  err( darkroom.SDF==false or tab.sdfOutput:allLE1(), "rigel.newFunction: sdf output rate is not <=1, but is: "..tostring(tab.sdfOutput) )

  err( types.isType(tab.inputType), "rigel.newFunction: input type must be type, but is: "..tostring(tab.inputType) )
  err( types.isType(tab.outputType), "rigel.newFunction: output type must be type, but is "..tostring(tab.outputType).." ("..tab.name..")" )

  err( type(tab.delay)=="number" or types.isHandshakeAny(tab.inputType) or types.isHandshakeAny(tab.outputType) or tab.inputType==types.null(), "rigel.newFunction: missing delay? fn '"..tab.name.."' inputType:"..tostring(tab.inputType).." outputType:"..tostring(tab.outputType) )
  
  if tab.inputType:isArray() or tab.inputType:isTuple() then err(darkroom.isBasic(tab.inputType),"array/tup module input is not over a basic type?") end
  if tab.outputType:isArray() or tab.outputType:isTuple() then err(darkroom.isBasic(tab.outputType),"array/tup module output is not over a basic type? "..tostring(tab.outputType) ) end
  
  if tab.globalMetadata==nil then tab.globalMetadata={} end

  assert(getmetatable(tab)==nil)
  if tab.systolicModule~=nil then
    print("systolic module already exists?", tab.name, getmetatable(tab))
    assert(false)
  end

  err( type(tab.stateful)=="boolean", "rigel.newFunction: stateful should be bool" )

  if tab.requires==nil then tab.requires={} end
  if tab.provides==nil then tab.provides={} end

  for instance,fnmap in pairs(tab.requires) do
    err( darkroom.isInstance(instance), "Require list should be instance/fnlist table, but is: "..tostring(instance) )
    err( type(fnmap)=="table", "Require list fnmap should be table, but is: "..tostring(fnmap) )
    for fn,_ in pairs(fnmap) do
      err( type(fn)=="string", "Require list should be instance/fnlist table, but is: "..tostring(fn) )
    end
  end

  for instance,fnlist in pairs(tab.provides) do
    err( darkroom.isInstance(instance), "Provides list should be instance/fnlist table, but is: "..tostring(instance) )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Provides list should be instance/fnlist table, but is: "..tostring(fn) )
    end
  end

  assert(getmetatable(tab)==nil)
  setmetatable( tab, darkroomFunctionMT )

  return tab
end


darkroomModuleMT = {
__tostring = function(tab)
  local res = {}

  local mt = getmetatable(tab)
  setmetatable(tab,nil)
  local tabstr = tostring(tab)
  setmetatable(tab,mt)
  
  table.insert(res,"Rigel Module "..tab.name.." ("..tabstr..")")

  table.insert(res,"  Functions:")
  for fnname,fn in pairs(tab.functions) do
    local fnmt = getmetatable(fn)
    setmetatable(fn,nil)
    local fntabstr = tostring(fn)
    setmetatable(fn,fnmt)

    table.insert(res,"    "..fnname.."("..fntabstr..") : "..tostring(fn.inputType).."->"..tostring(fn.outputType)..", "..tostring(fn.sdfInput).."->"..tostring(fn.sdfOutput))
  end

  table.insert(res,"  Stateful: "..tostring(tab.stateful))
    
  table.insert(res,"  Metadata:")
  for k,v in pairs(tab.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end

  if J.keycount(tab.requires)>0 then
    table.insert(res,"  Requires:")
    for inst,fnlist in pairs(tab.requires) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Requires: (none)")
  end

  if J.keycount(tab.provides)>0 then
    table.insert(res,"  Provides:")
    for inst,fnlist in pairs(tab.provides) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Provides: (none)")
  end

  if J.keycount(tab.instanceMap)==0 then
    table.insert(res,"  Internal Instances: (none)")
  else
    table.insert(res,"  Internal Instances:")
    for inst,_ in pairs(tab.instanceMap) do
      table.insert(res,"    "..inst.name..":"..inst.module.name)
    end
  end
  
  return table.concat(res,"\n")
end,
__index=function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = darkroomModuleFunctions[key]
  if v~=nil then return v end

  if key=="systolicModule" then
    return buildAndCheckSystolicModule(tab,true)
  elseif key=="terraModule" then
    return buildAndCheckTerraModule(tab)
  end
end
}

function darkroomModuleFunctions:instantiate( name, X )
  err( name==nil or type(name)=="string", "instantiate: input should be string")
  err( X==nil, "instantiate: too many arguments" )
  
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiate(name, self )
  return res
end

-- this function doesn't check that the module struct is valid, it only creates the data structure.
-- (ie that input type is correct, or that requires table is consistant).
function darkroom.newModule( tab, X )
  err( type(tab)=="table","newModule: input should be table" )
  err( type(tab.name)=="string", "newModule: name must be string" )
  err( type(tab.functions)=="table", "newModule: function list must be table (map from fn name to fn)")
  err( tab.makeSystolic==nil or type(tab.makeSystolic)=="function", "newModule: makeSystolic should be function")
  err( type(tab.stateful)=="boolean","newModule: stateful should be boolean" )
  err( tab.makeTerra==nil or type(tab.makeTerra)=="function","newModule: makeTerra should be function, but is: "..tostring(tab.makeTerra))
  err( X==nil, "newModule: too many arguments" )

  if tab.globalMetadata==nil then tab.globalMetadata={} end

  if tab.instanceMap==nil then tab.instanceMap={} end
  if tab.requires==nil then tab.requires={} end
  if tab.provides==nil then tab.provides={} end

  err( type(tab.instanceMap)=="table", "newModule: instanceMap should be table")
  for inst,_ in pairs(tab.instanceMap) do
    assert( darkroom.isInstance(inst) )
  end

  for instance,fnlist in pairs(tab.requires) do
    err( darkroom.isInstance(instance), "Require list should be instance/fnlist table, but is: "..tostring(instance) )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Require list should be instance/fnlist table, but is: "..tostring(fn) )
    end
  end

  for instance,fnlist in pairs(tab.provides) do
    err( darkroom.isInstance(instance), "Provides list should be instance/fnlist table, but is: "..tostring(instance) )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Provides list should be instance/fnlist table, but is: "..tostring(fn) )
    end
  end

  assert(getmetatable(tab)==nil)

  return setmetatable( tab, darkroomModuleMT )
end

moduleGeneratorFunctions = {}
moduleGeneratorMT = {
__index=moduleGeneratorFunctions,
__tostring = function(tab) return "ModuleGenerator" end
}

moduleGeneratorInstanceCallsiteMT = {
__call = function(tab,...)
  local rawarg = {...}
  if darkroom.isIR(rawarg[1]) then
    assert(false)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling a function generator with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local res = tab.moduleGeneratorInstance.module.fnCallback(tab.moduleGeneratorInstance,tab.fnname,arg)

    J.err( darkroom.isPlainFunction(res), "ModuleGenerator fnCallback should return plain function, but returned: "..tostring(res))
    return res
  else
    J.err(false, "Called module generator instance callsite with something other than a Rigel value or table ("..tostring(rawarg[1])..")? Make sure you call function generator with curly brackets {}")
  end
end,
__tostring = function(tab) return "ModuleGeneratorInstanceCallsite" end
}

function darkroom.isModuleGeneratorInstanceCallsite(t) return getmetatable(t)==moduleGeneratorInstanceCallsiteMT end

moduleGeneratorInstanceMT = {
__index = function(tab, key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  return setmetatable({moduleGeneratorInstance=tab,fnname=key}, moduleGeneratorInstanceCallsiteMT)
end,
__tostring = function(tab) return "ModuleGeneratorInstance "..tab.name.." of moduleGenerator "..tab.module.name end
}

function moduleGeneratorFunctions:instantiate(name)
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = { name=name, module=self }

  -- mixin initial config
  for k,v in pairs(self.instanceInitial) do
    assert(res[k]==nil)
    res[k] = v
  end
  
  return setmetatable( res, moduleGeneratorInstanceMT )
end

-- fnCallback: called when 
--     input: moduleGeneratorInstance, functionname, generator args
--     output: a plain Rigel function
--     (mutate the moduleGeneratorInst to store whatever data you need to reconstruct the module later)
-- completeFn: called when we need to actually instantiate the module for real
--     input: a module generator instance
--     output: should return a plain Rigel module
--     (the framework will then mutate the moduleGeneratorInstance to point to the plain module)
-- instInitial: this is a table of values which are mixed into the moduleGeneratorInstance at start of time
function darkroom.newModuleGenerator( namespace, name, requiredArgs, optArgs, instInitial, fnCallback, completeFn, X )
  err( type(namespace)=="string", "newModuleGenerator: namespace must be string" )
  err( type(name)=="string", "newModuleGenerator: name must be string, but is: "..tostring(name) )
  err( type(instInitial)=="table", "newModuleGenerator: instance initial values must be table" )
  err( type(fnCallback)=="function", "newModuleGenerator: fnCallback must be a lua function" )
  err( type(completeFn)=="function", "newModuleGenerator: completeFn must be a lua function" )
  err( X==nil, "newModuleGenerator: too many args")
  
  local tab = { namespace=namespace, name=name, requiredArgs=requiredArgs, optArgs=optArgs, fnCallback=fnCallback, completeFn=completeFn, instanceInitial = instInitial}
  return setmetatable( tab, moduleGeneratorMT )
end

function darkroom.isPlainModule(m) return getmetatable(m)==darkroomModuleMT end
function darkroom.isModuleGenerator(m) return getmetatable(m)==moduleGeneratorMT end
function darkroom.isModule(m) return darkroom.isPlainModule(m) or darkroom.isModuleGenerator(m) end

darkroomIRFunctions = {}
darkroomIRFunctions.isIR=true
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {}--{__index = darkroomIRFunctions}
function darkroomIRMT.__index(tab,key)
  local res = rawget(tab,key)
  if res~=nil then return res end

  if darkroomIRFunctions[key]~=nil then
    return darkroomIRFunctions[key]
  end

  if type(key)=="number" and (darkroom.isHandshakeArray(tab.type) or darkroom.isHandshakeTuple(tab.type) or tab.type:is("HandshakeArrayFramed") or tab.type:is("HandshakeTriggerArray")) then
    local res = darkroom.selectStream(nil,tab,key)
    rawset(tab,key,res)
    return res
  elseif type(key)=="number" and darkroom.isBasic(tab.type) and (tab.type:isArray() or tab.type:isTuple()) then
    local G = require "generators"
    local res = G.Index{key}(tab)
    rawset(tab,key,res)
    return res
  end
end

darkroomIRMT.__tostring = function(tab)
  local res
  if tab.kind=="input" then
    res = "local "..tab.name.." = R.input("..tostring(tab.type)..")"
  elseif tab.kind=="constant" then
    res = "local "..tab.name.." = R.constant('"..tab.name.."',"..tostring(tab.value)..","..tostring(tab.type)..")"
  elseif tab.kind=="applyMethod" then
    if #tab.inputs==0 then
      res = tab.name.." = "..tab.inst.name..":"..tab.fnname.."()"
    else
      res = tab.name.." = "..tab.inst.name..":"..tab.fnname.."("..tab.inputs[1].name..")"
    end
  elseif tab.kind=="apply" then
    if #tab.inputs==0 then
      res = "local "..tab.name.." = "..tab.fn.name.."()"
    else
      if tab.fn.generator~=nil then
        local gen
        if type(tab.fn.generator)=="string" then
          -- legacy
          gen = tab.fn.generator
        else
          gen = tab.fn.generator.namespace.."."..tab.fn.generator.name.."{"
          local lst = {}
          for k,v in pairs(tab.fn.generatorArgs) do
            if k=="luaFunction" or k=="rigelFunction" then
              table.insert(lst,k.."=SKIP")
            else
              table.insert(lst,k.."="..tostring(v))
            end
          end
          gen = gen..table.concat(lst,",").."}"
        end
        
        res = "local "..tab.name.." = "..gen.."("..tab.inputs[1].name..")  -- Module:"..tab.fn.name
      else
        res = "local "..tab.name.." = "..tab.fn.name.."("..tab.inputs[1].name..")"
      end
    end
  elseif tab.kind=="selectStream" then
    res = tab.name.." = "..tab.inputs[1].name.."["..tab.i.."] -- selectStream"
  elseif tab.kind=="statements" then
    res = "statements{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name..","
    end
    res = res.."}"
  elseif tab.kind=="concat" or tab.kind=="concatArray2d" then
    res = "local "..tab.name.." = R.concat('"..tab.name.."',{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name
      if k~=#tab.inputs then res = res.."," end
    end
    res = res.."})"
  else
    res = "NYI-print of "..tab.kind
  end

  if darkroom.SDF then
    res = res .." -- RateOut:"..tostring(tab.rate)
    local util = tab:utilization()
    if util~=nil then res=res.." Util:"..tostring(util[1]).."/"..tostring(util[2]) end
  end

  if true then
    res = res .. " type:"..tostring(tab.type)
  end
  
  return res
end

local darkroomInstanceFunctions = {}
local darkroomInstanceMT = {
  __index = function( tab, key )
    local v = rawget(tab, key)
    if v ~= nil then return v end
    v = darkroomInstanceFunctions[key]
    if v~=nil then return v end

    if darkroom.isModule(tab.module) and tab.module.functions[key]~=nil then
      return darkroom.newInstanceCallsite( tab, key )
    end
  end,
  __call = function(tab,inp,X)
    if darkroom.isPlainFunction(tab.module) then
      return darkroom.applyMethod("INSTCALL",tab,"process",inp,X)
    else
      assert(false)
    end
  end,
  __tostring = function(tab) return "Instance "..tab.name.." of "..tostring(tab.module) end}

-- we want there to be a 1-1 correspondence between systolic instances and rigel instances
darkroomInstanceFunctions.toSystolicInstance = J.memoize(function(tab,X)
  assert(X==nil)
  err( S.isModule(tab.module.systolicModule), "Missing systolic module for instance '"..tab.name.."' of module '"..tab.module.name.."'")
  return tab.module.systolicModule:instantiate(tab.name)
end)

-- get a reference to the instance in terra
darkroomInstanceFunctions.terraReference = J.memoize(function(tab,X)
  local MT = require "modulesTerra"
  return MT.terraReference(tab)
end)

function darkroomInstanceFunctions:vInput()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input"
  elseif darkroom.isInstanceCallsite(self.module) then
    return self.module.instance.name.."_"..self.module.functionName.."_input"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputData()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input["..(types.extractData(self.module.inputType):verilogBits()-1)..":0]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputValid()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input["..(types.lower(self.module.inputType):verilogBits()-1).."]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputReady()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_ready"
  elseif darkroom.isInstanceCallsite(self.module) then
    return self.module.instance.name.."_"..self.module.functionName.."_ready"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutput()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output"    
  elseif darkroom.isInstanceCallsite(self.module) then
    return self.module.instance.name.."_"..self.module.functionName
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputData()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output["..(types.extractData(self.module.outputType):verilogBits()-1)..":0]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputValid()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output["..(types.lower(self.module.outputType):verilogBits()-1).."]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputReady()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_ready_downstream"
  elseif darkroom.isInstanceCallsite(self.module) then
    return self.module.instance.name.."_"..self.module.functionName.."_ready_downstream"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:toVerilog()
  if darkroom.isPlainFunction(self.module) then

    local vstr = {}
    if self.module.inputType~=types.null() then
      table.insert(vstr,"wire ["..(types.lower(self.module.inputType):verilogBits()-1)..":0] "..self.name.."_process_input;\n")
      if types.isHandshakeAny(self.module.inputType) then 
        table.insert(vstr,"wire ["..(types.extractReady(self.module.inputType):verilogBits()-1)..":0] "..self.name.."_ready;\n")
      end
    end

    if self.module.outputType~=types.null() then
      table.insert(vstr,"wire ["..(types.lower(self.module.outputType):verilogBits()-1)..":0] "..self.name.."_process_output;\n")
      if types.isHandshakeAny(self.module.outputType) then
        table.insert(vstr,"wire ["..(types.extractReady(self.module.outputType):verilogBits()-1)..":0] "..self.name.."_ready_downstream;\n")
      end
    end
    
    table.insert(vstr,self.module.name.." "..self.name.."(.CLK(CLK)")
    if self.module.stateful then table.insert(vstr,",.reset(reset)") end

    if self.module.inputType~=types.null() then
      table.insert(vstr,",.process_input("..self.name.."_process_input)")
      if types.isHandshakeAny(self.module.inputType) then 
        table.insert(vstr,",.ready("..self.name.."_ready)")
      end
    end

    if self.module.outputType~=types.null() then
      table.insert(vstr,",.process_output("..self.name.."_process_output)")
      if types.isHandshakeAny(self.module.outputType) then
        table.insert(vstr,",.ready_downstream("..self.name.."_ready_downstream)")
      end
    end
    
    for inst,fnmap in pairs(self.module.requires) do
      for fnname,_ in pairs(fnmap) do
        local fn = inst.module.functions[fnname]

        if fn.inputType~=types.null() then
          table.insert(vstr,",."..inst.name.."_"..fnname.."_input("..inst.name.."_"..fnname.."_input)")
          if types.isHandshakeAny(fn.inputType) then 
            table.insert(vstr,",."..inst.name.."_"..fnname.."_ready("..inst.name.."_"..fnname.."_ready)")
          end
        end

        if fn.outputType~=types.null() then
          table.insert(vstr,",."..inst.name.."_"..fnname.."_output("..inst.name.."_"..fnname.."_output)")
          if types.isHandshakeAny(fn.outputType) then 
            table.insert(vstr,",."..inst.name.."_"..fnname.."_ready_downstream("..inst.name.."_"..fnname.."_ready_downstream)")
          end
        end
      end
    end
    
    table.insert(vstr,");\n")
    return table.concat(vstr,"")
  elseif darkroom.isInstanceCallsite(self.module) then
    return ""
  else
    print("Error, NYI instance:toVerilog() of "..tostring(self))
    assert(false)
  end
end

function darkroom.isInstance(t) return getmetatable(t)==darkroomInstanceMT end
function darkroom.newIR(tab)
  assert( type(tab) == "table" )
  err( type(tab.name)=="string", "IR node "..tab.kind.." is missing name" )
  err( type(tab.loc)=="string", "IR node "..tab.kind.." is missing loc" )
  err( type(tab.inputs)=="table","IR node "..tab.kind..", inputs should be table")
  assert( #tab.inputs==J.keycount(tab.inputs))
  for i=1,#tab.inputs do
    assert(darkroom.isIR(tab.inputs[i]))
  end
  
  IR.new( tab )
  local r = setmetatable( tab, darkroomIRMT )
  r:typecheck()

  if darkroom.SDF then
    r.rate = r:calcSDF()
    assert(SDF.isSDF(r.rate))
  end
  
  return r
end

function darkroomIRFunctions:calcSDF( )
  local res
  if self.kind=="input" or self.kind=="constant" then
    err( SDF.isSDF(self.rate),"input missing SDF?")
    res = self.rate
  elseif self.kind=="apply" or (self.kind=="applyMethod" and darkroom.isPlainFunction(self.inst.module)) then

    local fn = self.fn
    if self.kind=="applyMethod" and darkroom.isPlainFunction(self.inst.module) then
      fn = self.inst.module
    end
    
    if #self.inputs==1 then
      res =  fn:sdfTransfer(self.inputs[1].rate, "APPLY "..self.name.." "..self.loc)
      if DARKROOM_VERBOSE then print("APPLY",self.name,fn.kind,"rate",res) end
    elseif #self.inputs==0 then
      err( SDF.isSDF(self.rate),"nullary apply missing SDF?")
      res = self.rate
    else
      -- ??
      assert(false)
    end
  elseif self.kind=="applyMethod" then
    -- spaghetti code: see case in 'apply' above
    assert( darkroom.isModule(self.inst.module) )

    if #self.inputs==0 or self.inputs[1].type==types.null() then
      err( self.inst.module.functions[self.fnname].sdfExact==true or types.isHandshakeAny(self.inst.module.functions[self.fnname].outputType)==false, "null input applyMethod '"..self.fnname.."' on module '"..self.inst.module.name.."' should have sdfExact==true")
      res = self.inst.module.functions[self.fnname].sdfOutput
    elseif self.inst.module.functions[self.fnname].sdfExact==true then
      err( self.inst.module.functions[self.fnname].inputType==types.null() or self.inst.module.functions[self.fnname].sdfInput:equals(self.inputs[1].rate),"applyMethod: input rate ("..tostring(self.inputs[1].rate)..") does not match expected rate declared by the instance ("..tostring(self.inst.module.functions[self.fnname].sdfInput).."). Function '"..self.fnname.."' on instance '"..self.inst.name.."' of module '"..self.inst.module.name.."'.")
      res = self.inputs[1].rate
    elseif #self.inputs==1 then
      res =  self.inst.module.functions[self.fnname]:sdfTransfer(self.inputs[1].rate, "APPLYMETHOD "..self.name.." "..self.loc)
    else
      assert(false)
    end
  elseif self.kind=="concat" or self.kind=="concatArray2d" then
    if self.inputs[1]:outputStreams()==0 then
      -- for non-handshake values (i.e. no streams), we just count this as 1 output stream
      -- this is the _very_ rare case where we're doing multi-rate statically timed pipelines
      
      local IR
      -- all input rates must match!
      for key,i in ipairs(self.inputs) do
        assert(#self.inputs[key].rate==1)
        
        if IR==nil then
          IR=self.inputs[key].rate[1]
        else
          local rateList = ""
          for _,v in ipairs(self.inputs) do rateList = rateList..","..tostring(v.rate) end
          err(self.inputs[key].rate[1][1]==IR[1] and self.inputs[key].rate[1][2]==IR[2], "SDF "..self.kind.." rate mismatch \n"..rateList.."\n"..tostring(self).." "..self.loc)
        end
      end
      res = {IR}
      if DARKROOM_VERBOSE then print("CONCAT",self.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
    else
      res = {}
      for k,v in ipairs(self.inputs) do
        assert(#v.rate==1)
        table.insert(res, v.rate[1])
      end
      
      if DARKROOM_VERBOSE then
        print("CONCAT",self.name)
        for k,v in ipairs(res[2]) do
          print("        concat["..tostring(k).."] converged=",v,"RATE",res[1][k][1],res[1][k][2])
        end
      end
    end
  elseif self.kind=="statements" then
    res = self.inputs[1].rate
  elseif self.kind=="selectStream" then
    assert( #self.inputs==1 )
    err( self.inputs[1].rate[self.i+1]~=nil, "selectStream "..tostring(self.i)..": stream does not exist! There are only "..tostring(#self.inputs[1].rate).." streams."..self.loc )
    res = {self.inputs[1].rate[self.i+1]}
  else
    print("NYI? sdftotal of node: ",self.kind,self)
    assert(false)
  end

  err( SDFRate.isSDFRate(res), "calcSDF returned something other than SDF rate? "..self.kind )
  return SDF(res)
end

function darkroomIRFunctions:outputStreams() return darkroom.streamCount(self.type) end

-- This converts our stupid internal represention into the SDF 'rate' used in the SDF paper
-- i.e. the number you multiply the input/output rate by to make the rates match.
-- Meaning for us: if < 1, then not is underutilized (sits idle). If >1, then node is
-- oversubscribed (will limit speed)
function darkroomIRFunctions:utilization()
  if self.kind=="apply" then
    assert(#self.inputs<=1)
    local total = self.rate
    err(SDF.isSDF(total),"missing rate? "..self.kind..","..self.name)
    local res = SDFRate.fracMultiply({total[1][1],total[1][2]},{self.fn.sdfOutput[1][2],self.fn.sdfOutput[1][1]})
    if DARKROOM_VERBOSE then print("SDF RATE",self.name,res[1],res[2],"sdfINP",self.fn.sdfInput[1][1],self.fn.sdfInput[1][2],"SDFOUT",self.fn.sdfOutput[1][1],self.fn.sdfOutput[1][2]) end
    assert(SDFRate.isFrac(res))
    return res
  else
    return nil
  end
end

-- assuming that the inputs are running at {1,1}, wht is the lowest/highest SDF utilization in this DAG?
-- (this will limit the speed of the whole pipe)
-- In our implementaiton, the utilization of any node can't be >1, so if the highest utilization is >1, we need to scale the throughput of the whole pipe
darkroomIRFunctions.sdfExtremeRate = J.memoize(
  function(self, highest )
    local highestRate -- this is a frac
    self:visitEach(
      function(n)
        if n.kind=="apply" then
          local util = n:utilization()

          local Uniform = require "uniform"
          
          if highestRate==nil then
            highestRate={util[1],util[2]}
          else
            local cond
            if highest then
              cond = Uniform(highestRate[1]*util[2]):gt(util[1]*highestRate[2])
            else
              cond = Uniform(highestRate[1]*util[2]):lt(util[1]*highestRate[2])
            end
            
            highestRate[1] = cond:sel(highestRate[1],util[1])
            highestRate[2] = cond:sel(highestRate[2],util[2])
          end
        end
      end)

    if highestRate==nil then
      -- this can happen if we have no function calls (no other operators have utilization)
      return {1,1}
    end
    
    return highestRate
  end)

function darkroomIRFunctions:typecheck()
  local n = self
  if n.kind=="apply" or (n.kind=="applyMethod" and darkroom.isPlainFunction(n.inst.module)) then
    local fn = n.fn
    if n.kind=="applyMethod" and darkroom.isPlainFunction(n.inst.module) then fn=n.inst.module end
    
    err( fn.registered==false or fn.registered==nil, "Error, applying registered type! "..fn.name)
    if #n.inputs==0 then
      err( fn.inputType==types.null(), "Missing function argument, "..n.loc)
    else
      assert( types.isType( n.inputs[1].type ) )
      err( n.inputs[1].type==fn.inputType, "Input type mismatch to function '"..fn.name.."'. Is "..tostring(n.inputs[1].type).." but should be "..tostring(fn.inputType)..", "..n.loc)
    end
    n.type = fn.outputType
  elseif n.kind=="applyMethod" then
    -- spaghetti code: see case in 'apply' above
    assert( darkroom.isModule(n.inst.module) )
          
    err( darkroom.isPlainFunction(n.inst.module.functions[n.fnname]), "Error, module does not have a method named '..n.fnname..'!")
    
    if n.inputs[1]==nil then
      err( n.inst.module.functions[n.fnname].inputType==types.null(), "Error, method '"..n.fnname.."' on instance '"..n.inst.name.."' of module '"..n.inst.module.name.."' was passed no input, but expected an input (of type "..tostring(n.inst.module.functions[n.fnname].inputType)..")")
    else
      err( n.inst.module.functions[n.fnname].inputType==n.inputs[1].type, "Error, input to function '"..n.fnname.."' should have type '"..tostring(n.inst.module.functions[n.fnname].inputType).."', but was passed type '"..tostring(n.inputs[1].type).."'")
    end
    
    n.type = n.inst.module.functions[n.fnname].outputType
  elseif n.kind=="input" then
  elseif n.kind=="constant" then
  elseif n.kind=="concat" then
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = darkroom.HandshakeTuple( J.map(n.inputs, function(v,k) err(darkroom.isHandshake(v.type),"concat: if one input is Handshake, all inputs must be Handshake, but idx "..tostring(k).." is "..tostring(v.type)); return darkroom.extractData(v.type) end) )
    elseif darkroom.isHandshakeTrigger(n.inputs[1].type) then
      -- there's no reason for HandshakeTuple to exist...
      err( false, "HandshakeTriggers should be concatinated with 'concatArray2d', not 'concat'")
    elseif darkroom.isBasic(n.inputs[1].type) then
      n.type = types.tuple( J.map(n.inputs, function(v) err(darkroom.isBasic(v.type),"concat: if one input is basic, all inputs must be basic"); return v.type end) )
    else
      err(false,"concat: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="concatArray2d" then
    J.map( n.inputs, function(i,k) err(i.type==n.inputs[1].type, "All inputs to concatArray2d must have same type! index "..tostring(k-1).." is type "..tostring(i.type)..", but index 0 is "..tostring(n.inputs[1].type)) end )
    
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = darkroom.HandshakeArray( darkroom.extractData(n.inputs[1].type), n.W, n.H )
    elseif n.inputs[1].type:is("HandshakeFramed") then
      n.type = types.HandshakeArrayFramed( darkroom.extractData(n.inputs[1].type), n.inputs[1].type.params.mixed, n.inputs[1].type.params.dims, n.W, n.H )
    elseif darkroom.isBasic(n.inputs[1].type) then
      n.type = types.array2d( n.inputs[1].type, n.W, n.H )
    elseif darkroom.isHandshakeTrigger(n.inputs[1].type) then
      for k,v in ipairs(n.inputs) do
        err(types.isHandshakeTrigger(v.type),"concat: is one input is HandshakeTrigger, all inputs must be HandshakeTrigger")
      end
      n.type = types.HandshakeTriggerArray(#n.inputs)
    else
      err(false,"concatArray2d: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="statements" then
    n.type = n.inputs[1].type
  elseif n.kind=="selectStream" then
    if darkroom.isHandshakeArray(n.inputs[1].type) or n.inputs[1].type:is("HandshakeArrayFramed") then
      err( n.i < n.inputs[1].type.params.W, "selectStream index out of bounds. inputType: "..tostring(n.inputs[1].type).." index:"..tostring(n.i))
      err( n.j==nil or (n.j < n.inputs[1].type.params.H), "selectStream index out of bounds")
      if n.inputs[1].type:is("HandshakeArrayFramed") then
        n.type = types.HandshakeFramed(n.inputs[1].type.params.A,n.inputs[1].type.params.mixed,n.inputs[1].type.params.dims)
      else
        n.type = darkroom.Handshake(n.inputs[1].type.params.A)
      end
    elseif darkroom.isHandshakeTriggerArray(n.inputs[1].type) then
      err( n.i < n.inputs[1].type.params.W, "selectStream index out of bounds")
      err( n.j==nil or (n.j < n.inputs[1].type.params.H), "selectStream index out of bounds")
      n.type = darkroom.HandshakeTrigger
    elseif darkroom.isHandshakeTuple(n.inputs[1].type) then
      err( n.i < #n.inputs[1].type.params.list, "selectStream index out of bounds")
      n.type = darkroom.Handshake(n.inputs[1].type.params.list[n.i+1])
    else
      err(false, "selectStream input must be array or tuple of handshakes, but is "..tostring(n.inputs[1].type) )
    end
  else
    print("Rigel Typecheck NYI ",n.kind)
    assert(false)
  end
end

function darkroomIRFunctions:codegenSystolicReady( module )
  local readyinp
  local readyout

  -- if we have nil->Handshake(A) types, we have to drive these ready chains somehow (and they're not connected to input)
  local readyPipelines={}

  -- remember, we're visiting the graph in reverse here.
  -- if the node takes I inputs, we return a lua array of size I
  -- for each input i in I:
  -- if that input has 1 input stream, we out[i] is a systolic bool value
  -- if that input has N input streams, we out[i] is a systolic array of bool values
  -- if that input is 0 streams, out[i] is nil
  
  self:visitEachReverse(
    function(n, args)
      
      local input
      
      -- why do we need to support multiple readers of a HS stream? (ie ANDing the ready bits?)
      -- A stream may be read by multi selectStreams, which is OK.
      -- However: why can't we just special-case expect all multiple readers to be selectStreams? It seems like this should work.
      -- Note 1: Take a look at modulesTerra.lambda... it basically implements this that way
      -- Note 2: one issue is that it's very important that this function returns a systolic value of the correct type for
      --         every intermediate! We can return/examine any intermediate, and it must have the right type!
      --         don't try to special case by having this function return intermediates as lua arrays of bools or something.
      
      for k,i in pairs(args) do
        local parentKey = i[2]
        local value = i[1]
        local thisi = value[parentKey]
        
        if types.isHandshake(n.type) or types.isHandshakeTrigger(n.type) or n.type:is("HandshakeFramed") then
          assert(systolicAST.isSystolicAST(thisi))
          assert(thisi.type:isBool())
          
          if input==nil then
            input = thisi
          else
            input = S.__and(input,thisi)
          end
        elseif n:outputStreams()>1 or types.isHandshakeArray(n.type) then
          assert(systolicAST.isSystolicAST(thisi))
          
          if types.isHandshakeTmuxed(n.type) or types.isHandshakeArrayOneHot(n.type) then
            assert(J.keycount(args)==1) -- NYI
            input = thisi
          else
            assert(thisi.type:isArray() and thisi.type:arrayOver():isBool())
            
            if input==nil then
              input = thisi
            else
              local r = {}
              for i=0,n:outputStreams()-1 do
                r[i+1] = S.__and(S.index(input,i),S.index(thisi,i))
              end
              input = S.cast(S.tuple(r),types.array2d(types.bool(),n:outputStreams()))
            end
          end
        else
          --err(false,"no output streams? why is this getting a ready bit? "..n.loc)
          -- this is OK - fifo:store() for example has nil output
        end
      end
      
      if J.keycount(args)==0 then
        -- this is the output of the pipeline
        assert(readyinp==nil)
        assert(n:parentCount(self)==0)
        
        if n:outputStreams()==1 then
          readyinp = S.parameter( "ready_downstream", types.bool() )
          input = readyinp
        elseif n:outputStreams()>1 then
          readyinp = S.parameter( "ready_downstream", types.array2d(types.bool(),n:outputStreams()) )
          input = readyinp
        else
          -- this is ok: ready bit may be totally internal to the module
          readyinp = S.parameter( "ready_downstream", types.null() )
          input = readyinp
        end
      else
        -- if any downstream nodes are selectStream, they'd better all be selectStream, and the count had better match
        local anySS = false
        local allSS = true
        for dsNode,_ in n:parents(self) do
          if dsNode.kind=="selectStream" then
            anySS = true
          else
            allSS = false
          end
        end
        
        err( anySS==allSS,"If any consumers are selectStream, all consumers must be selectStream "..n.loc )
        err( allSS==false or J.keycount(args)==n:outputStreams(), "Unconnected output? Module expects "..tostring(n:outputStreams()).." stream readers, but only "..tostring(J.keycount(args)).." were found. "..n.loc )
        
        if n:outputStreams()>=1 and n:parentCount(self)>1 then
          err(allSS,"Error, a Handshaked, multi-reader node is being consumed by something other than a selectStream? Handshaked nodes with multiple consumers should use broadcastStream. "..n.loc)
        end
      end
      
      local res
      
      if n.kind=="input" then
        assert(readyout==nil)
        readyout = input
      elseif n.kind=="apply" then
        res = {module:lookupInstance(n.name):ready(input)}
        if n.fn.inputType==types.null() then
          table.insert(readyPipelines, res[1])
        end
      elseif n.kind=="applyMethod" then
        local inst = module:lookupInstance(n.inst.name)
        res = {inst[n.fnname.."_ready"](inst, input)}
        
        if n.inst.module.functions[n.fnname].inputType==types.null() then
          -- eg fifo:load_ready()... nothing else will drive this, so we need to add it
          table.insert(readyPipelines,res[1])
        end
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        err( input.type:isArray() and input.type:arrayOver():isBool(), "Error, tuple should have an input type of array of N ready bits")
        
        -- tuple has N input streams, N output streams
        
        res = {}
        local i=0
        for i=0,n:outputStreams()-1 do
          table.insert(res, S.index(input,i) )
        end
      elseif n.kind=="statements" then
        res = {input}
        for i=2,#n.inputs do
          if n.inputs[i]:outputStreams()==1 then
            res[i] = S.constant(true,types.bool())
          elseif n.inputs[i]:outputStreams()>1 then
            local r = {}
            for ii=1,n.inputs[i]:outputStreams() do table.insert(r,S.constant(true,types.bool())) end
            res[i] = S.cast(S.concat(r), types.array2d(types.bool(),n.inputs[i]:outputStreams()) ) 
          else
            -- res[i]=nil
          end
        end
        
      elseif n.kind=="selectStream" then
        
        res = {}
        
        res[1] = {}
        for i=1,n.inputs[1]:outputStreams() do
          if i-1==n.i then
            res[1][i] = input
          else
            res[1][i] = S.constant(true,types.bool())
          end
        end
        
        res[1] = S.cast( S.tuple(res[1]),types.array2d(types.bool(),n.inputs[1]:outputStreams()) )
      else
        print("missing ready wiring of op - "..n.kind)
        assert(false)
      end
      
      -- now, validate that the output is what we expect
      err( #n.inputs==0 or type(res)=="table","res should be table "..n.kind.." inputs "..tostring(#n.inputs))
      
      for k,i in ipairs(n.inputs) do
        if types.isHandshake(i.type) or i.type:is("HandshakeFramed") then
          err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
          err(systolicAST.isSystolicAST(res[k]) and res[k].type:isBool(), "incorrect output format of ready function. This node: kind='"..n.kind.."' "..tostring(n).." input index "..tostring(k).."/"..(#n.inputs).." (with input type "..tostring(i.type)..", and input name "..i.name..") is "..tostring(res[k].type).." but expected bool, "..n.loc )
        elseif types.isHandshakeTrigger(i.type) then
          --assert(#res==1)
          assert(res[k].type:isBool())
        elseif i:outputStreams()>1 or types.isHandshakeArray(i.type) then
          
          err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
          if types.isHandshakeTmuxed(i.type) then
            err( res[k].type:isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          elseif types.isHandshakeArrayOneHot(i.type) then
            err( res[k].type==types.uint(8),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          else
            err(res[k].type:isArray() and res[k].type:arrayOver():isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          end
        elseif i:outputStreams()==0 then
          if res[k]~=nil then
            err( res[k].type==types.null(), "incorrect ready bit format. input "..tostring(k).." outputStreams()==0, however ready type is '"..tostring(res[k].type).."'. kind:'"..n.kind.."' node: "..tostring(n).." input node: "..tostring(i).." - "..n.loc)
          end
        else
          print("NYI "..tostring(i.type))
          assert(false)
        end
      end
      -- end validate
      
      return res
    end, true)
  
  return readyinp, readyout, readyPipelines
end

function darkroomIRFunctions:codegenSystolic( module )
  assert(Ssugar.isModuleConstructor(module))
  return self:visitEach(
    function(n, inputs)
      if n.kind=="input" then
        local res = {module:lookupFunction("process"):getInput()}
        if darkroom.isRV(n.type) then res[2] = module:lookupFunction("ready"):getInput() end
        return res
      elseif n.kind=="applyMethod" then
        local I = module:lookupInstance(n.inst.name)
        local inp = inputs[1]
        if inp~=nil then inp=inp[1] end
        return {I[n.fnname](I,inp)}
      elseif n.kind=="apply" then
        err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process")~=nil, "Error, missing process fn? "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process"):getInput().type==darkroom.lower(n.fn.inputType), "Systolic input type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule:lookupFunction("process"):getInput().type).." but should be "..tostring(darkroom.lower(n.fn.inputType)).." (Rigel type: "..tostring(n.fn.inputType)..")" )

        if n.fn.outputType==types.null() then
          err(n.fn.systolicModule.functions.process.output==nil or n.fn.systolicModule.functions.process.output.type==types.null(), "Systolic output type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule.functions.process.output).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        else
          err( n.fn.systolicModule:lookupFunction("process").output.type == darkroom.lower(n.fn.outputType), "Systolic output type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule:lookupFunction("process").output.type).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        end
        
        err(type(n.fn.stateful)=="boolean", "Missing stateful annotation "..n.fn.name)
        
        local I = module:add( n.fn.systolicModule:instantiate(n.name) )

        if n.fn.stateful then
          if darkroom.isHandshakeAny( n.fn.inputType ) or
          darkroom.isHandshakeAny(n.fn.outputType) then
            err(I.module.functions["reset"]~=nil,"missing reset function? instance '"..I.name.."' of module '"..I.module.name.."'")
            module:lookupFunction("reset"):addPipeline( I:reset(nil,module:lookupFunction("reset"):getValid()) )
          else
            module:lookupFunction("reset"):addPipeline( I:reset() )
          end
        end
        
        if n.fn.inputType==types.null() then
          return { I:process() }
        elseif darkroom.isV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready() }
        elseif darkroom.isRV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready(inputs[1][2]) }
        elseif darkroom.isRV(n.type) then
          -- the strange basic->RV case
          err( false, "You shouldn't use Basic->RV directly, loc "..n.loc )
        else
          return {I:process(inputs[1][1])}
        end
      elseif n.kind=="constant" then
        return {S.constant( n.value, n.type )}
      elseif n.kind=="concat" then
        return {S.tuple( J.map(inputs,function(i) return i[1] end) ) }
      elseif n.kind=="concatArray2d" then
        local outtype
        if darkroom.isHandshakeArray(n.type) or n.type:is("HandshakeTriggerArray")then
          outtype = n.type.structure
        else
          outtype = types.array2d(darkroom.lower(n.type:arrayOver()),n.W,n.H)
        end
        return {S.cast(S.tuple( J.map(inputs,function(i) return i[1] end) ), outtype) }
      elseif n.kind=="statements" then
        for i=2,#inputs do
          module:lookupFunction("process"):addPipeline( inputs[i][1] )
        end
        return inputs[1]
      elseif n.kind=="selectStream" then
        return {S.index(inputs[1][1],n.i)}
      else
        print(n.kind)
        assert(false)
      end
    end)
end


function darkroom.isPlainFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isFunction(t) return darkroom.isPlainFunction(t) or darkroom.isFunctionGenerator(t) or darkroom.isModuleGeneratorInstanceCallsite(t) end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

-- function argument
function darkroom.input( ty, sdfRate )
  err( types.isType( ty ), "darkroom.input: first argument should be type" )
  err( sdfRate==nil or SDFRate.isSDFRate(sdfRate), "input: second argument should be SDF rate or nil")

  if sdfRate==nil then
    sdfRate=J.broadcast({1,1}, math.max(1,darkroom.streamCount(ty)) )
  end

  err( darkroom.streamCount(ty)==0 or darkroom.streamCount(ty)==#sdfRate, "rigel.input: number of streams in type "..tostring(ty).." ("..tostring(darkroom.streamCount(ty))..") != number of SDF streams passed in ("..tostring(#sdfRate)..")" )
  
  return darkroom.newIR( {kind="input", type = ty, name="input", id={}, inputs={}, rate=SDF(sdfRate), loc=getloc()} )
end

darkroom.instantiate = function( name, mod, X )
  err( type(name)=="string", "instantiate: name must be string")
  err( darkroom.isModule(mod) or darkroom.isPlainFunction(mod), "instantiate: module must be a Rigel module or function, but is: "..tostring(mod) )
  err( X==nil, "darkroom.instantiate: too many arguments" )

  local t = {name=name, module=mod }
  return setmetatable(t, darkroomInstanceMT)
end

-- sdfRateOverride: override the firing rate of this apply. useful for nullary modules.
function darkroom.apply( name, fn, input, sdfRateOverride )
  err( type(name) == "string", "first argument to apply must be name" )
  err( darkroom.isFunction(fn), "second argument to apply must be a darkroom function" )
  err( input==nil or darkroom.isIR( input ), "last argument to apply must be darkroom value or nil" )
  err( sdfRateOverride==nil or SDFRate.isSDFRate(sdfRateOverride), "sdfRateOverride must be SDF rate" )

  if input==nil and sdfRateOverride==nil then
    sdfRateOverride={{1,1}}
  end
  
  if darkroom.isFunctionGenerator(fn) then
    local arglist = {}
    for k,v in pairs(fn.curriedArgs) do arglist[k] = v end
    local ty, rate
    if arglist.type==nil then ty=input.type end
    if arglist.rate==nil then rate=input.rate end
    fn = fn{ty,rate}
  end

  if darkroom.isPlainFunction(fn)==false then
    print("Function generator '"..fn.name.."' could not be resolved into a module?")
    print("missing args: "..fn:listRequiredArgs())
    assert(false)
  end

  if sdfRateOverride~=nil then
    sdfRateOverride=SDF(sdfRateOverride)
  end
  
  return darkroom.newIR( {kind = "apply", name = name, loc=getloc(), fn = fn, inputs = {input}, rate=sdfRateOverride } )
end

function darkroom.applyMethod( name, inst, fnname, input, X )
  err( type(name)=="string", "name must be string")
  err( darkroom.isInstance(inst), "applyMethod: second argument should be instance" )
  err( type(fnname)=="string", "fnname must be string")
  err( input==nil or darkroom.isIR( input ), "applyMethod: last argument should be rigel value or nil, but is: "..tostring(input) )
  err( X==nil, "applyMethod: too many arguments")

  return darkroom.newIR( {kind = "applyMethod", name = name, fnname=fnname, loc=getloc(), inst = inst, inputs = {input} } )
end

-- can be called either as constant(name,value,ty) or constant(value,ty)
function darkroom.constant( name, value, ty, X )
  err( X==nil, "rigel.constant: too many arguments" )

  local res = {kind="constant", loc=getloc(), inputs = {}, rate=SDF{1,1}}
  if type(name)=="string" then
    res.name = name
    res.value = value
    res.type = ty
  else
    res.defaultName=true
    res.name="const"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
    res.value = name
    res.type = value
    err( ty==nil, "rigel.constant: too many arguments" )
  end
  
  --err( types.isType(res.type), "rigel.constant: type must be rigel type" )
  if res.type==nil then
    -- user just called constant(val), try to guess type
    res.type = types.valueToType(res.value)
  end
  
  res.type:checkLuaValue(res.value)

  return darkroom.newIR( res )
end
darkroom.c = darkroom.constant

-- this can be called with either (name,{}) or just {}
function darkroom.concat( name, t, X )

  local r = {kind="concat", loc=getloc(), inputs={} }

  if type(name)=="string" then
    r.name = name
  elseif (name==nil and type(t)=="table") or (type(name)=="table" and t==nil) then
    r.defaultName=true
    r.name="concat"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1

    if type(name)=="table" and t==nil then
      t = name
    end
  else
    err( type(name)=="string", "first concat input should be name")
  end
  
    
  err( type(t)=="table", "tuple input should be table of darkroom values" )
  err( X==nil, "rigel.concat: too many arguments")
  
  J.map(t, function(n,k) err(darkroom.isIR(n),"tuple input is not a darkroom value"); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

function darkroom.concatArray2d( name, t, W, H, X )
  err( type(t)=="table", "array2d input should be table of darkroom values" )
  err(X==nil, "rigel concatArray2d too many arguments")

  err( type(W)=="number", "W must be number")
  if H==nil then H=1 end
  err( type(H)=="number", "H must be number")

  local r = {kind="concatArray2d", name=name, loc=getloc(), inputs={}, W=W, H=H}

  if name==nil then
    r.defaultName=true
    r.name="concatArray2d"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
  end
  
  J.map(t, function(n,k) assert(darkroom.isIR(n)); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

function darkroom.selectStream( name, input, i, X )

  local r = {kind="selectStream"}
  
  if name==nil then
    r.defaultName=true
    r.name="selectStream"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
  else
    err( type(name)=="string", "first selectStream input should be name")
    r.name=name
  end

  err( type(i)=="number", "i must be number")
  err( darkroom.isIR(input), "input must be IR")
  err(X==nil,"selectStream: too many arguments")

  r.i=i
  r.loc = getloc()
  r.inputs={input}
  
  return darkroom.newIR(r)
end

function darkroom.statements( t )
  err( type(t)=="table", "statements: argument should be table" )
  err( #t>0 and J.keycount(t)==#t, "statements: argument should be lua array")
  J.map(t, function(i) err(darkroom.isIR(i), "statements: argument should be rigel value") end )
  return darkroom.newIR{kind="statements",inputs=t,loc=getloc(),name="__&STATEMENTS"}
end

-- this should go somewhere else
function darkroom.handshakeMode(output)
  local HANDSHAKE_MODE = false
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.fn.inputType) or darkroom.isHandshakeAny(n.fn.outputType)
      elseif n.kind=="applyMethod" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.inst.module.functions[n.fnname].inputType) or darkroom.isHandshakeAny(n.inst.module.functions[n.fnname].outputType)
      end
    end)
  return HANDSHAKE_MODE
end

function darkroom.export(t)
  if t==nil then t=_G end

  rawset(t,"c",darkroom.constant)
end

return darkroom
