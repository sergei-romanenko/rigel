local IR = require("ir")
local types = require("types")
local typecheckAST = require("typecheck")
local systolic={}

systolicModuleFunctions = {}
systolicModuleMT={__index=systolicModuleFunctions}

systolicInstanceFunctions = {}

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
end

function sanitize(s)
  s = s:gsub("%[","_")
  s = s:gsub("%]","_")
  s = s:gsub("%,","_")
  s = s:gsub("%.","_")
  return s
end

local function checkast(ast) err( systolicAST.isSystolicAST(ast), "input should be a systolic AST" ); return ast end

local function typecheck(ast)
  return systolicAST.new( typecheckAST(ast) )
end

function checkReserved(k)
  if k=="input" or k=="output" or k=="reg" then
    print("Error, variable name ",k," is a reserved keyword in verilog")
    assert(false)
  end
end

local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||"}

function declareReg(ty, name, initial, comment)
  assert(type(name)=="string")

  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..valueToVerilog(initial,ty)
  end

  if ty:isBool() then
    return "reg "..name..initial..";"..comment.."\n"
  else
    return "reg ["..(ty:sizeof()*8-1)..":0] "..name..initial..";"..comment.."\n"
 end
end

function declareWire(ty, name, str, comment)
  assert( types.isType(ty) )
  assert(type(str)=="string" or str==nil)

  if comment==nil then comment="" end

  if str == nil or str=="" then
    str = ""
  else
    str = " = "..str
  end

  if ty:isBool() then
    return "wire "..name..str..";"..comment.."\n"
  else
    return "wire ["..(ty:sizeof()*8-1)..":0] "..name..str..";"..comment.."\n"
  end
end

function declarePort( ty, name, isInput )
  assert(type(name)=="string")

  local t = "input "
  if isInput==false then t = "output " end

  if ty:isBool()==false then
    t = t .."["..(ty:sizeof()*8-1)..":0] "
  end
  t = t..name
  
  return t
end

function channelIndex( ty, c )
  assert(darkroom.type.isType(ty))
  assert(type(c)=="number")

  if ty:channels()==1 then
    return ""
  elseif ty:baseType():isBool() then
    assert(false)
  else
    return "["..(c*ty:baseType():sizeof()*8-1)..":"..((c-1)*ty:baseType():sizeof()*8).."]"
  end
end

function numToVarname(x)
  if x>0 then return x end
  if x==0 then return "0" end
  return "m"..math.abs(x)
end

function pointerToVarname(x)
  assert(type(x)=="table")
  return tostring(x):sub(10)
end

function valueToVerilogLL(value,signed,bits)
  assert(type(value)=="number")

  if signed then
    if value==0 then
      return bits.."'d0"
    elseif value<0 then
      return "-"..bits.."'d"..math.abs(value)
    else
      return bits.."'d"..value
    end
  else
    assert(value>=0)
    return bits.."'d"..math.abs(value)
  end
end

function valueToVerilog(value,ty)

  if ty:isInt() then
    assert(type(value)=="number")
    if value==0 then
      return (ty:sizeof()*8).."'d0"
    elseif value<0 then
      return "-"..(ty:sizeof()*8).."'d"..math.abs(value)
    else
      return (ty:sizeof()*8).."'d"..value
    end
  elseif ty:isUint() then
    assert(type(value)=="number")
    assert(value>=0)
    return (ty:sizeof()*8).."'d"..value
  elseif ty:isBool() then
    if value then
      return "1'd1"
    else
      return "1'd0"
    end
  else
    assert(false)
  end
end

function systolicModuleFunctions:instantiate(name)
  err( type(name)=="string", "instantiation name must be a string")
  return systolicInstance.new({kind="module",module=self,name=name,callsites={}})
end

systolicFunctionFunctions = {}
systolicFunctionMT={__index=systolicFunctionFunctions}

systolicFunction = {}
function systolic.isFunction(t)
  return getmetatable(t)==systolicFunctionMT or getmetatable(t)==systolicFunctionConstructorMT
end

function systolic.lambda( name, input, output, outputName, pipelines, valid )
  err( systolicAST.isSystolicAST(input), "input must be a systolic AST" )
  err( systolicAST.isSystolicAST(output) or output==nil, "output must be a systolic AST or nil" )
  err( input.kind=="parameter", "input must be a parameter" )
  err( type(outputName)=="string", "output name must be a string")
  
  if pipelines==nil then pipelines={} end
  if valid==nil then valid = systolic.parameter(name.."_valid", types.bool()) end
  if output~=nil then output = output:addValid( valid ) end
  pipelines = map( pipelines, function(n) return n:addValid(valid) end )

  local t = { name=name, input=input, output = output, outputName=outputName, pipelines=pipelines, valid=valid }

  return setmetatable(t,systolicFunctionMT)
end

function systolicInstanceFunctions:getDelay( fn )
  assert( systolic.isFunction(fn) )
  return self.module:getDelay( fn )
end

function systolicInstanceFunctions:toVerilog()
  return self.module:instanceToVerilog(self)
end

-- some functions don't modify state. These do not need a valid bit
function systolicFunctionFunctions:isPure()
  return false
--  return foldl( andop, true, map( self.assignments, function(n) return n.dst.kind=="output" end ) )
end

function systolicFunctionFunctions:isAccessor()
  return #self.inputs==0
end


function systolicFunctionFunctions:getDefinitionKey()
  assert(self.pure)
  return self
end

local function binop(lhs, rhs, op)
  lhs, rhs = checkast(lhs), checkast(rhs)
  return typecheck({kind="binop",op=op,inputs={lhs,rhs},loc=getloc()})
end

local function unary(expr, op)
  expr = convert(expr)
  return typecheck(darkroom.ast.new({kind="unary",op=op,expr=expr}):copyMetadataFrom(expr))
end

systolic._callsites = {}
systolicInstance = {}
function systolicInstance.new(tab)
  return setmetatable(tab,systolicInstanceMT)
end

function systolic.isInstance(tab)
  return getmetatable(tab)==systolicInstanceMT
end

systolicInstanceMT={
__index = function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = systolicInstanceFunctions[key]

  if v==nil and rawget(tab,"kind")=="module" then
    -- try to find key in function tab
    local fn = rawget(tab,"module").functions[key]
    if fn~=nil then
      return function(self, inp, valid)
        err( inp==nil or systolicAST.isSystolicAST(inp), "input must be a systolic ast or nil" )
        
        tab.callsites[fn.name] = tab.callsites[fn.name] or {}
        table.insert(tab.callsites[fn.name],1)

        if inp~=nil then err( inp.type==fn.input.type, "Error, input type to function incorrect. Is "..tostring(inp.type).." but should be "..tostring(fn.input.type) ) end

        local otype = types.null()
        if fn.output~=nil then otype = fn.output.type end

        local t = { kind="call", inst=self, func=fn, type=otype, loc=getloc(), inputs={inp,valid} }
        
        return systolicAST.new(t)
             end
    end
    
  end
  return v
end}

systolicASTFunctions = {}
setmetatable(systolicASTFunctions,{__index=IR.IRFunctions})
systolicASTMT={__index = systolicASTFunctions,
__add=function(l,r) return binop(l,r,"+") end, 
__sub=function(l,r) return binop(l,r,"-") end,
  __newindex = function(table, key, value)
                    darkroom.error("Attempt to modify systolic AST node")
                  end}

function systolicASTFunctions:init()
  setmetatable(self,nil)
  systolicAST.new(self)
end

-- ops
function systolic.index( expr, idx, idy )
  assert(systolicAST.isSystolicAST(expr))
  err( type(idx)=="number", "idx should be a number" )
  if idy==nil then idy=0 end
  return typecheck({kind="index", idx=idx, idy=idy, inputs={expr}, loc=getloc()})
end

function systolic.cast( expr, ty )
  err( systolicAST.isSystolicAST(expr), "input to cast must be a systolic ast")
  err( types.isType(ty), "input to cast must be a type")
  return typecheck({kind="cast",inputs={expr},type=ty,loc=getloc()})
end

function systolic.constant( v, ty )
  err( type(v)=="number" or type(v)=="boolean", "systolic constant must be bool or number")
  err( types.isType(ty), "constant type must be a type")
  return typecheck({ kind="constant", value=v, type = ty, loc=getloc(), inputs={} })
end

function systolic.tuple( tab )
  err( type(tab)=="table", "input to tuple should be a table")
  local res = {kind="tuple",inputs={}, loc=getloc()}
  map(tab, function(v,k) err( systolicAST.isSystolicAST(v), "input to tuple should be table of ASTs"); res.inputs[k]=v end )
  return typecheck(res)
end

function systolic.select( cond, a, b )
  cond, a, b = convert(cond), convert(a), convert(b)
  return typecheck(darkroom.ast.new({kind="select",inputs={cond,a,b}}):copyMetadataFrom(cond))
end

function systolic.le(lhs, rhs) return binop(lhs,rhs,"<=") end
function systolic.eq(lhs, rhs) return binop(lhs,rhs,"==") end
function systolic.lt(lhs, rhs) return binop(lhs,rhs,"<") end
function systolic.ge(lhs, rhs) return binop(lhs,rhs,">=") end
function systolic.gt(lhs, rhs) return binop(lhs,rhs,">") end
function systolic.__or(lhs, rhs) return binop(lhs,rhs,"or") end
function systolic.__and(lhs, rhs) return binop(lhs,rhs,"and") end
function systolic.neg(expr) return unary(expr,"-") end

function systolicASTFunctions:cname(c)
  return self:name().."_c"..c
end


function checkForInst(inst, scopes)
  assert(systolicInstance.isSystolicInstance(inst))

  local fnd = false
  for k,scope in ipairs(scopes) do
    fnd = fnd or scope.instanceMap[inst]~=nil
  end
  
  if fnd==false then
    print("missing instance "..inst.name.." (kind "..inst.kind..")")
    map(scopes, function(n) print("scope",n.name) end)
    assert(false)
  end
end

-- check that all of the variables refered to are actually in scope
-- scopes goes from innermost (index 1) to outermost (index n)
function systolicASTFunctions:checkVariables(scopes)
  assert(type(scopes)=="table")

  local function astcheck(n)
    if n.kind=="readinput" or n.kind=="reg" or n.kind=="ram128" or n.kind=="call" then
      checkForInst(n.inst, scopes)
    end

    if n.kind=="fndefn" then
      local i=1
      while n["dst"..i] do
        checkForInst(n["dst"..i], scopes)
        i = i + 1
      end
    end

    if n.kind=="call" and n.func:isPure()==false then
      assert(systolicAST.isSystolicAST(n.valid))
    end
  end

  self:visitEach(astcheck)
end

function systolicASTFunctions:checkInstances( instMap )
  self:visitEach( 
    function(n)
      if n.kind=="call" then
        err( instMap[n.inst]~=nil, "Error, instance "..n.inst.name.." is not a member of this module, "..n.loc )
      end
    end)
end

function systolicASTFunctions:disablePipelining()
  return self:S("*"):process(
    function(n)
      if n.kind=="reg" then
        -- these things we can't disable pipelining on
      else
        local nn = n:shallowcopy()
        nn.pipelined=false
        return systolicAST.new(nn):copyMetadataFrom(n)
      end
    end)
end

function systolicASTFunctions:pipeline()
  local pipelineRegisters = {}
  local fnDelays = {}

  local delayCache = {}
  local function getDelayed( node, delay )
    delayCache[node] = delayCache[node] or {}
    if delay==0 then return node
    elseif delayCache[node][delay]==nil then
      local reg = systolic.module.reg( node.type ):instantiate(node.name.."_pipeline"..delay)
      table.insert( pipelineRegisters, reg )
      local d = getDelayed(node, delay-1)
      delayCache[node][delay] = reg:delay( d )
    end
    return delayCache[node][delay]
  end

  local finalOut = self:visitEach(
    function( inpn, args )
      local n = inpn:shallowcopy()
      n.inputs={}
      for k,v in pairs(args) do n.inputs[k] = v[1] end
      n = systolicAST.new(n)

      if n.kind=="parameter" or n.kind=="constant" or n.kind=="module" then
        return {n, 0}
      elseif n.kind=="index" or n.kind=="cast" then
        -- passthrough, no pipelining
        return {n, args[1][2]}
      elseif n.kind=="call" or n.kind=="tuple" or n.kind=="binop" then
        -- tuples and calls happen to be almost identical

        if n.kind=="call" and n.func.input.type==types.null() then
          -- no inputs, so this gets put at time 0
          return { n, n.inst.module:getDelay( n.func.name ) }
        else
          -- delay match on all inputs
          local maxd = 0
          map(args, function(a) maxd=math.max(maxd,a[2]) end)
          
          for k,v in pairs(n.inputs) do
            -- insert delays so that each input is delayed the same amount
            n.inputs[k] = getDelayed( args[k][1], maxd - args[k][2])
          end
          
          local internalDelay = 0
          if n.kind=="call" then 
            internalDelay= n.inst.module:getDelay( n.func.name ) 
          elseif n.kind=="binop" then 
            n = getDelayed(n,1)
            internalDelay = 1 
          end

          return { n, maxd+internalDelay }
        end
      elseif n.kind=="fndefn" then
        if #n.inputs==0 then
          -- its possible for functions to do nothing
          fnDelays[n.fn.name] = 0
        else
          fnDelays[n.fn.name] = args[1][2]
        end
        return {n,0}
      else
        print(n.kind)
        assert(false)
      end
    end)

  return finalOut[1], pipelineRegisters, fnDelays
end

function systolicASTFunctions:addValid( validbit )
  assert( systolicAST.isSystolicAST(validbit) )
  return self:process(
    function(n)
      if n.kind=="call" and n.inputs[2]==nil then
        n.inputs[2] = validbit
        return systolicAST.new(n)
      end
    end)
end

function systolicASTFunctions:toVerilog( options, scopes )
  local clockedLogic = {}
  local declarations = {}

  local finalOut = self:visitEach(
    function(n, args)
      local finalResult
      -- if finalResult is already a wire, we don't need to assign it to a wire at the end
      -- if wire==false, then finalResult is an expression, and can't be used multiple times
      local wire = false

      if n.kind=="call" then
        if n.inst.module.options.lateInstantiation then
          local decl
          finalResult, decl, wire = n.inst.module:instanceToVerilog( n.inst, n.func.name, args[1], args[2] )
          table.insert( declarations, decl )
        else
          if n.func:isPure()==false then
            table.insert(declarations, "assign "..n.inst.name.."_"..n.func.valid.name.." = "..args[2].."; // call valid")
          end
          
          if n.func.input.type~=types.null() then table.insert(declarations, "assign "..n.inst.name.."_"..n.func.name.."_"..n.func.input.name.." = "..args[1].."; // call input") end
          
          if n.func.output~=nil then
            finalResult =  n.inst.name.."_"..n.func.name.."_"..n.func.outputName
            wire = true
          else
            finalResult =  "__NILVALUE_ERROR"
          end     
        end
      elseif n.kind=="constant" then
        local function cconst( ty, val )
          if ty:isArray() then
            return "{"..table.concat( map(range(ty:channels()), function(c) return cconst(n.type:baseType(), val[c])  end) ).."}"
          else
            return valueToVerilog(val, ty)
          end
        end
        finalResult = "("..cconst(n.type,n.value)..")"
      elseif n.kind=="fndefn" then
        table.insert(declarations,"  // function: "..n.fn.name..", pure="..tostring(n.fn:isPure()))
        if n.fn.output~=nil then table.insert(declarations,"assign "..n.fn.outputName.." = "..args[1]..";") end
        finalResult = "_ERR_NULL_FNDEFN"
      elseif n.kind=="module" then
        for _,v in pairs(n.module.functions) do
          table.insert( declarations,"  // function: "..v.name.." delay="..n.module:getDelay(v.name) )
        end
        finalResult = "__ERR_NULL_MODULE"
      elseif n.kind=="index" then
        if n.inputs[1].type:isArray() then
          local flatIdx = (n.inputs[1].type:arrayLength())[1]*n.idy+n.idx
          local sz = n.inputs[1].type:arrayOver():bits()
          finalResult = args[1].."["..((flatIdx+1)*sz-1)..":"..(flatIdx*sz).."]"
        elseif n.inputs[1].type:isUint() or n.inputs[1].type:isInt() then
          table.insert( resDeclarations, declareWire( n.type:baseType(), n:cname(c), "", " // index result" ))
          table.insert( resDeclarations, "assign "..n:cname(c).." = "..inputs["expr"][c].."["..n.index1.constLow_1.."]; // index")
          finalResult = n:cname(c)
        elseif n.inputs[1].type:isTuple() then
          local lowbit = 0
          for k,v in pairs(n.inputs[1].type.list) do if k-1<n.idx then lowbit = lowbit + v:bits() end end
          finalResult = args[1].."["..(lowbit+n.inputs[1].type.list[n.idx+1]:bits()-1)..":"..lowbit.."]"
        else
          print(n.expr.type)
          assert(false)
        end
      elseif n.kind=="tuple" then
        finalResult="{"..table.concat(reverse(args),",").."}"
      elseif n.kind=="cast" then

          local expr
          local cmt = " // cast "..tostring(n.inputs[1].type).." to "..tostring(n.type)

          local function dobasecast( expr, fromType, toType )
            assert(type(expr)=="string")

            if fromType:isUint() and (toType:isInt() or toType:isUint()) and fromType.precision <= toType.precision then
              -- casting smaller uint to larger or equal int or uint. Don't need to sign extend
              return expr
            elseif toType:isInt() and fromType:isInt() and toType.precision > fromType.precision then
              -- casting smaller int to larger int. must sign extend
              return "{ {"..(8*(toType:sizeof() - fromType:sizeof())).."{"..expr.."["..(fromType:sizeof()*8-1).."]}},"..expr.."["..(fromType:sizeof()*8-1)..":0]}"
            elseif (fromType:isUint() or fromType:isInt()) and (toType:isInt() or toType:isUint()) and fromType.precision>toType.precision then
              -- truncation. I don't know how this works
              return expr
            elseif fromType:isInt() and toType:isUint() and fromType.precision == toType.precision then
              -- int to uint with same precision. I don't know how this works
              return expr
            else
              print("FAIL TO CAST",fromType,"to",toType)
              assert(false)
            end
          end

          if n.type:isArray() and n.inputs[1].type:isTuple()==true then
            err( #n.inputs[1].type.list == n.type:channels(), "tuple to array cast sizes don't match" )
            for k,v in pairs(n.inputs[1].type.list) do
              err( v==n.type:arrayOver(), "NYI - tuple to array cast, all tuple types must match array type")
            end
            expr = args[1] 
          elseif n.type:isArray() and n.inputs[1].type:isArray()==false and n.inputs[1].type:isTuple()==false then
            expr = "{"..table.concat( map(range(n.type:channels()), function(n) return args[1] end),",").."}" -- broadcast
            cmt = " // broadcast "..tostring(n.inputs[1].type).." to "..tostring(n.type)
          elseif n.inputs[1].type:isArray() and n.type:isArray()==false and n.inputs[1].type:arrayOver():isBool() and (n.type:isUint() or n.type:isInt()) then
            assert(false)
            -- casting an array of bools (bitfield) to an int or uint
            expr = "}"
            for c=1,n.expr.type:channels() do
              if c>1 then expr = ","..expr end
              expr = inputs.expr[c]..expr
            end
            expr = "{"..expr
          elseif n.type:isArray() and n.inputs[1].type:isArray() and n.type:baseType()==n.inputs[1].type:baseType() then
            assert(false)
            assert(n.type:channels() == n.expr.type:channels())
            expr = inputs.expr[c]
            cmt = " // cast, array size change from "..tostring(n.expr.type).." to "..tostring(n.type)
          elseif n.type:isArray() and n.inputs[1].type:isArray()  then
            assert(false)
            assert(n.type:arrayLength() == n.expr.type:arrayLength())
            -- same shape arrays, different base types
            expr = dobasecast( inputs.expr[c], n.expr.type:baseType(), n.type:baseType() )
          else
            expr = dobasecast( args[1], n.inputs[1].type, n.type )
          end

          finalResult = expr
      elseif n.kind=="parameter" then
        finalResult = n.name
        wire = true
      elseif n.kind=="array" then
        assert(false)
      else
        local resTable = {}
        for c=0,n.type:channels()-1 do
          local res
          local sub = "["..((c+1)*n.type:baseType():bits()-1)..":"..(c*n.type:baseType():bits()).."]" 

          if n.kind=="binop" then

            if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
              if n.type:baseType():isBool() and n.lhs.type:baseType():isInt() and n.rhs.type:baseType():isInt() then
                res = "($signed("..args[1]..sub..")"..n.op.."$signed("..inputs.rhs[c]..sub.."));"
              elseif n.type:baseType():isBool() and n.lhs.type:baseType():isUint() and n.rhs.type:baseType():isUint() then
                res = "(("..args[1]..")"..n.op.."("..inputs.rhs[c].."));"
              else
                print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
                assert(false)
              end
            elseif n.type:isBool() then
              local op = binopToVerilogBoolean[n.op]
              if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
              addstat(n.pipeline, callsite..n:name().."_c"..c, inputs.lhs[c]..op..inputs.rhs[c]..";")
            else
              local op = binopToVerilog[n.op]
              if type(op)~="string" then print("OP",n.op); assert(false) end
              local lhs = args[1]
              if n.inputs[1].type:baseType():isInt() then lhs = "$signed("..lhs..")" end
              local rhs = args[2]
              if n.inputs[2].type:baseType():isInt() then rhs = "$signed("..rhs..")" end
              res = "("..lhs..op..rhs..")"
            end

          elseif n.kind=="unary" then
          addInput("expr")
          getInputs()
          thisDelay = 1

          if n.op=="abs" then
            if n.type:baseType():isInt() then
              table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c) ))
              table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs")
              res = callsite..n:cname(c)
            else
              return inputs.expr[c] -- must be unsigned
            end
          elseif n.op=="-" then
            assert(n.type:baseType():isInt())
            table.insert(resDeclarations, declareReg(n.type:baseType(), callsite..n:cname(c)))
            table.insert(resClockedLogic, callsite..n:cname(c).." <= -"..inputs.expr[c].."; // unary sub")
            res = callsite..n:cname(c)
          else
            print(n.op)
            assert(false)
          end
        elseif n.kind=="select" or n.kind=="vectorSelect" then
          addInput("cond"); addInput("a"); addInput("b");
          getInputs()

          if n.pipeline then
            thisDelay = 1
            table.insert( resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c), "", " // "..n.kind.." result" ))
          else
            thisDelay = 0
            table.insert( resDeclarations, declareWire( n.type:baseType(), callsite..n:cname(c), "", " // "..n.kind.." result" ))
          end

          local condC = 1
          if n.kind=="vectorSelect" then condC=c end

          --table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n")
          addstat( n.pipeline, callsite..n:cname(c), "("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n") 
          res = callsite..n:cname(c)
        else
          print(n.kind)
          assert(false)
        end

          table.insert( resTable, res )
        end

        finalResult = "{"..table.concat(resTable,",").."}"
      end

      -- if this value is used multiple places, store it in a variable
      if n:parentCount(self)>1 and wire==false then
        table.insert( declarations, declareWire( n.type, n.name.."USEDMULTIPLE", finalResult ) )
        return n.name.."USEDMULTIPLE"
      else
        return finalResult
      end
    end)

  local fin = table.concat(declarations,"\n")
  fin = fin.."\nalways @(posedge CLK) begin\n"
  fin = fin..table.concat(clockedLogic,"\n")
  fin = fin.."end\n"
  return fin
end

systolicAST = {}
function systolicAST.isSystolicAST(ast)
  return getmetatable(ast)==systolicASTMT
end

local __usedNameCnt = 0
function systolicAST.new(tab)
  assert(type(tab)=="table")
  if tab.scaleN1==nil then tab.scaleN1=0 end
  if tab.scaleD1==nil then tab.scaleD1=0 end
  if tab.scaleN2==nil then tab.scaleN2=0 end
  if tab.scaleD2==nil then tab.scaleD2=0 end
  assert(type(tab.inputs)=="table")
  if tab.name==nil then tab.name="unnamed"..__usedNameCnt; __usedNameCnt=__usedNameCnt+1 end
  assert(types.isType(tab.type))
  if tab.pipelined==nil then tab.pipelined=true end
  IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end

function systolic.parameter( name, ty )
  assert(type(name)=="string")
  checkReserved(name)
  assert( types.isType(ty) )
  return systolicAST.new({kind="parameter",name=name,type=ty,inputs={}})
end

--------------------------------------------------------------------
-- Module Definitions
--------------------------------------------------------------------
function systolic.isModule(t)
  return getmetatable(t)==userModuleMT or getmetatable(t)==fileModuleMT
end

systolic.module = {}
local __usedModuleNames = {}

userModuleFunctions={}
setmetatable(userModuleFunctions,{__index=systolicModuleFunctions})
userModuleMT={__index=userModuleFunctions}

function userModuleFunctions:instanceToVerilog( instance )
  local wires = {}
  local arglist = {}
    
  for fnname,fn in pairs(self.functions) do
    table.insert( wires, declareWire( types.bool(), instance.name.."_"..fn.valid.name ))
    table.insert( arglist, ", ."..fn.valid.name.."("..instance.name.."_"..fn.valid.name..")") 

    if fn.input.type~=types.null() then
     table.insert(wires,declareWire( fn.input.type, instance.name.."_"..fnname.."_"..fn.input.name )); 
      table.insert(arglist,", ."..fn.input.name.."("..instance.name.."_"..fnname.."_"..fn.input.name..")")
    end

    if fn.output~=nil then
      table.insert(wires, declareWire( fn.output.type, instance.name.."_"..fnname.."_"..fn.outputName))
      table.insert(arglist,", ."..fn.outputName.."("..instance.name.."_"..fnname.."_"..fn.outputName..")")
    end
  end

  return table.concat(wires)..self.name..[[ #(.INSTANCE_NAME("]]..instance.name..[[")) ]]..instance.name.."(.CLK(CLK)"..table.concat(arglist)..");\n\n"
end

function userModuleFunctions:lower()
  local mod = {kind="module", type=types.null(), inputs={}, module=self}

  for _,fn in pairs(self.functions) do
    local node = { kind="fndefn", fn=fn,type=types.null(), valid=fn.valid, inputs={fn.output} }
    for k,pipe in pairs(fn.pipelines) do
      table.insert( node.inputs, pipe )
    end

    node = systolicAST.new(node)
    table.insert( mod.inputs, node )
  end
  mod = systolicAST.new(mod)

  return mod
end

function userModuleFunctions:toVerilog()
  if self.verilog==nil and type(self.options.verilog)=="string" then
    self.verilog = self.options.verilog
  elseif self.verilog==nil then
    local astv = self.ast:toVerilog()
    local t = {}

    table.insert(t,"module "..self.name.."(input CLK")
  
    for fnname,fn in pairs(self.functions) do
      if fn:isPure()==false then table.insert(t,", input "..fn.valid.name) end
      if fn.input.type~=types.null() then table.insert(t,", input ["..(fn.input.type:sizeof()*8-1)..":0] "..fn.input.name) end
      if fn.output~=nil then table.insert(t,", "..declarePort( fn.output.type, fn.outputName, false ))  end
    end

    table.insert(t,");\n")
    table.insert(t,[[parameter INSTANCE_NAME="INST";]].."\n")
  
    for k,v in pairs(self.instances) do
      if v.module.options.lateInstantiation~=true then
        table.insert(t, v:toVerilog() )
      end
    end

    table.insert( t, self.ast:toVerilog() )
    table.insert(t,"endmodule\n\n")

    self.verilog = table.concat(t,"")
  end

  return self.verilog
end

function userModuleFunctions:getDependenciesLL()
  local dep = {}
  local depMap = {}

  for _,i in pairs(self.instances) do
    local deplist = i.module:getDependenciesLL()
    for _,D in pairs(deplist) do
      if depMap[D[1]]==nil then table.insert(dep, D) end
      depMap[D[1]]=1
    end
    if depMap[i.module]==nil then
      table.insert(dep,{i.module,i.module:toVerilog()})
      depMap[i.module]=1
    end
  end
  return dep
end

function userModuleFunctions:getDependencies()
  return table.concat(map(self:getDependenciesLL(), function(n) return n[2] end),"")
end

function userModuleFunctions:getDelay( fnname )
  return self.fndelays[fnname]
end

function systolic.module.new( name, fns, instances, options )
  assert(type(name)=="string")
  checkReserved(name)
  err( type(fns)=="table", "functions must be a table")
  map(fns, function(n) err( systolic.isFunction(n), "functions must be systolic functions" ) end )
  err( type(fns)=="table", "instances must be a table")
  map(instances, function(n) err( systolic.isInstance(n), "instances must be systolic instances" ) end )

  if options==nil then options={} end

  if __usedModuleNames[name]~=nil then
    print("Module name ",name, "already used")
    assert(false)
  end
  __usedModuleNames[name]=1

  -- We let users choose whatever parameter names they want. Check for duplicate variable names in functions.
  local _usedPname = {}
  for _,v in pairs(fns) do
    err( _usedPname[v.outputName]==nil, "output name "..v.outputName.." used somewhere else in module" )
    _usedPname[v.outputName]=1
    err( _usedPname[v.input.name]==nil, "input name "..v.input.name.." used somewhere else in module" )
    _usedPname[v.input.name]=1
    err( _usedPname[v.valid.name]==nil, "valid bit name "..v.valid.name.." used somewhere else in module" )
    _usedPname[v.valid.name]=1
  end

  local t = {name=name,kind="user",instances=instances,functions=fns, instanceMap={}, usedInstanceNames = {}, options=options,isComplete=false}
  map( instances, function(i) t.instanceMap[i]=1; t.usedInstanceNames[i.name]=1 end )
  setmetatable(t,userModuleMT)

  t.ast = t:lower()
  -- check that the instances refered to by this module are actually in the module
  t.ast:checkInstances( t.instanceMap )
  local pipelineRegisters
  t.ast, pipelineRegisters, t.fndelays = t.ast:pipeline()
  map( pipelineRegisters, function(p) table.insert( t.instances, p ) end )

  return t
end

----------------------------
regModuleFunctions={}
setmetatable(regModuleFunctions,{__index=systolicModuleFunctions})
regModuleMT={__index=regModuleFunctions}

function regModuleFunctions:instanceToVerilog( instance, fnname, inputVar, validVar )
  if fnname=="delay" then
    local decl = declareReg(self.type, instance.name, self.initial)
    decl = decl.."always @ (posedge CLK) begin "..instance.name.." <= "..inputVar.."; end"
    return instance.name, decl, true
  else
    print("regModuleFunctions:instanceToVerilog",fnname)
    assert(false)
  end
end
function regModuleFunctions:getDependenciesLL() return {} end
function regModuleFunctions:toVerilog() return "" end

function systolic.module.reg( ty, initial )
  err(types.isType(ty),"type must be a type")
  local t = {kind="reg",initial=initial,type=ty,options={lateInstantiation=true}}
  t.functions={}
  t.functions.delay={name="delay", output={type=ty}, input={name="DELAY_INPUT",type=ty},outputName="DELAY_OUTPUT"}
  t.functions.delay.isPure = function() return false end
  return setmetatable(t,regModuleMT)
end

-------------------
ram128ModuleFunctions={}
setmetatable(ram128ModuleFunctions,{__index=systolicModuleFunctions})
ram128ModuleMT={__index=ram128ModuleFunctions}
local __ram128 = {kind="ram128"}
setmetatable(__ram128,ram128ModuleMT)

function ram128ModuleFunctions:instanceToVerilog( instance )
    return [[ wire ]]..instance.name..[[_WE;
wire ]]..instance.name..[[_D;
wire ]]..instance.name..[[_writeOut;
wire ]]..instance.name..[[_readOut;
wire [6:0] ]]..instance.name..[[_writeAddr;
wire [6:0] ]]..instance.name..[[_readAddr;
RAM128X1D ]]..instance.name..[[  (
  .WCLK(CLK),
  .D(]]..instance.name..[[_D),
  .WE(]]..instance.name..[[_WE),
  .SPO(]]..instance.name..[[_writeOut),
  .DPO(]]..instance.name..[[_readOut),
  .A(]]..instance.name..[[_writeAddr),
  .DPRA(]]..instance.name..[[_readAddr));
]]
end

function systolic.module.ram128() return __ram128 end

--------------------
bramModuleFunctions={}
setmetatable(bramModuleFunctions,{__index=systolicModuleFunctions})
bramModuleMT={__index=bramModuleFunctions}

local __bram = {kind="bram"}
function bramModuleFunctions:instanceToVerilog( instance )
    local conf={name=self.name}
    conf.A={chunk=self.typeA:sizeof(),
           DI = self.name.."_DI",
           DO = self.name.."_DO",
           ADDR = self.name.."_addr",
           CLK = "CLK",
           WE = self.name.."_WE",
           readFirst = true}
    conf.B={chunk=self.typeA:sizeof(),
           DI = self.name.."_DI_B",
           DO = self.name.."_DO_B",
           ADDR = self.name.."_addr_B",
           CLK = "CLK",
           WE = "1'd0",
           readFirst = true}
    local addrbits = 10 - math.log(self.typeA:sizeof())/math.log(2)
    return [[wire ]]..self.name..[[_WE;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DI;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DI_B;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DO;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DO_B;
wire []]..addrbits..[[:0] ]]..self.name..[[_addr;
wire []]..addrbits..[[:0] ]]..self.name..[[_addr_B;
]]..table.concat(fixedBram(conf))
end
function systolic.module.bram( ) return __bram end
--------------------
fileModuleFunctions={}
setmetatable(fileModuleFunctions,{__index=systolicModuleFunctions})
fileModuleMT={__index=fileModuleFunctions}

function fileModuleFunctions:instanceToVerilog( instance )
--  return "FILELOL"
  if instance.callsites.read~=nil and instance.callsites.write==nil then
    local assn = ""
    for i=0,self.type:sizeof()-1 do
      assn = assn .. instance.name.."_read_out["..((i+1)*8-1)..":"..(i*8).."] = $fgetc("..instance.name.."_file); "
    end

    return [[integer ]]..instance.name..[[_file,r;
wire ]]..instance.name..[[_read_valid;
wire ]]..instance.name..[[_reset_valid;
reg []]..(self.type:sizeof()*8-1)..[[:0] ]]..instance.name..[[_read_out;
initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","r"); end
always @ (posedge CLK) begin 
  if (]]..instance.name..[[_read_valid) begin ]]..assn..[[ end 
  if (]]..instance.name..[[_reset_valid) begin r=$fseek(]]..instance.name..[[_file,0,0); end
end
]]
  elseif instance.callsites.read==nil and instance.callsites.write~=nil then
    local assn = ""
    for i=0,self.type:sizeof()-1 do
      assn = assn .. "$fwrite("..instance.name..[[_file, "%c", ]]..instance.name.."_write_input["..((i+1)*8-1)..":"..(i*8).."] ); "
    end

    return [[integer ]]..instance.name..[[_file,r;
wire ]]..instance.name..[[_write_valid;
wire ]]..instance.name..[[_reset_valid;
wire []]..(self.type:sizeof()*8-1)..[[:0] ]]..instance.name..[[_write_input;
initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","wb"); end
always @ (posedge CLK) begin 
  if (]]..instance.name..[[_write_valid) begin ]]..assn..[[ end 
  if (]]..instance.name..[[_reset_valid) begin r=$fseek(]]..instance.name..[[_file,0,0); end
end
]]
  else
    assert(false)
  end
end
function fileModuleFunctions:toVerilog() return "" end
function fileModuleFunctions:getDependenciesLL() return {} end
function fileModuleFunctions:getDelay(fnname)
  if fnname=="write" then
    return 0
  elseif fnname=="read" then
    return 1
  elseif fnname=="reset" then
    return 0
  else
    print(fnname)
    assert(false)
  end
end

function systolic.module.file( filename, ty)
  local res = {kind="file",filename=filename, type=ty, options={}}
  res.functions={}
  res.functions.read={name="read",output={type=ty},input={name="FREAD_INPUT",type=types.null()},outputName="out",valid={name="read_valid"}}
  res.functions.read.isPure = function() return false end
  res.functions.write={name="write",output={type=types.null()},input={name="input",type=ty},outputName="out",valid={name="write_valid"}}
  res.functions.write.isPure = function() return false end
  res.functions.reset = {name="reset",output={type=types.null()},input={name="input",type=types.null()},outputName="out",valid={name="reset_valid"}}
  res.functions.reset.isPure = function() return false end

  return setmetatable(res, fileModuleMT)
end

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a function
--------------------------------------------------------------------

systolicFunctionConstructor = {}
systolicFunctionConstructorMT={__index=systolicFunctionConstructor}

function systolic.lambdaConstructor( name, input, valid )
  err( systolicAST.isSystolicAST(input), "input must be a systolic AST" )
  if valid==nil then valid = systolic.parameter( name.."_valid", types.bool() ) end
  local t = {name=name, input=input, isComplete=false }
end

function systolicFunctionConstructor:complete()
  if self.isComplete==false then
    if self.returnValue==nil then self.returnValue={type=types.null()} end
    self.isComplete=true
  end
end

function systolicFunctionConstructor:output( expr )
  err( systolicAST.isSystolicAST(expr), "output must be a systolic AST" )
  self.returnValue = expr
end

function systolicFunctionConstructor:output( expr )

end

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a module
--------------------------------------------------------------------

systolicModuleConstructor = {}
systolicModuleConstructorMT={__index=systolicModuleConstructor}

function systolic.moduleConstructor( name, options )
  assert(type(name)=="string")
  checkReserved(name)
  if options==nil then options={} end

  local t = { name=name, options=options, functions={}, instances={}, isComplete=false, usedInstanceNames={}, instanceMap={} }

  return setmetatable( t, systolicModuleConstructorMT )
end

function systolicModuleConstructor:add( inst )
  err( systolic.isInstance(inst), "must be an instance" )
  assert( inst.kind=="module" or inst.kind=="reg" or inst.kind=="ram128" or inst.kind=="bram")

  checkReserved(inst.name)
  if self.usedInstanceNames[inst.name]~=nil then
    print("Error, name "..inst.name.." already in use")
    assert(false)
  end

  self.instanceMap[inst] = 1
  self.usedInstanceNames[inst.name] = 1

  table.insert(self.instances,inst)
  return inst
end


function systolicModuleConstructor:addFunction( fn )
  err( self.isComplete==false, "module is already complete")
  err( systolic.isFunction(fn), "input must be a systolic function")

  if self.usedInstanceNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  self.functions[fn.name]=fn
  fn.module = self
  return fn
end

function systolicModuleConstructor:complete()
  if self.isComplete==false then
    self.module = systolic.module.new( self.name, self.functions, self.instances, self.options )
    self.isComplete = true
  end
end

function systolicModuleConstructor:getDelay( fnname )
  self:complete()
  return self.module:getDelay( fnname )
end

function systolicModuleConstructor:toVerilog()
  self:complete()
  return self.module:toVerilog()
end

function systolicModuleConstructor:instantiate( name )
  self:complete()
  return self.module:instantiate(name)
end


return systolic