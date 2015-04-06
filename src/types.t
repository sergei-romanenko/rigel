types = {}

TypeFunctions = {}
TypeMT = {__index=TypeFunctions, __tostring=function(ty)
  if ty.kind=="bool" then
    return "bool"
  elseif ty.kind=="null" then
    return "null"
  elseif ty.kind=="int" then
    return "int"..ty.precision
  elseif ty.kind=="uint" then
    return "uint"..ty.precision
  elseif ty.kind=="float" then
    return "float"..ty.precision
  elseif ty.kind=="array" then
    return tostring(ty.over).."["..table.concat(ty.size,",").."]"
  elseif ty.kind=="tuple" then
    return "{"..table.concat(map(ty.list, function(n) return tostring(n) end), ",").."}"
  elseif ty.kind=="opaque" then
    return "opaque_"..ty.str
  end

  print("Error, typeToString input doesn't appear to be a type, ",ty.kind)
  assert(false)
end}

types._bool=setmetatable({kind="bool"}, TypeMT)
function types.bool() return types._bool end

types._null=setmetatable({kind="null"}, TypeMT)
function types.null() return types._null end

types._opaque={}
function types.opaque(str)
  types._opaque[str] = types._opaque[str] or setmetatable({kind="opaque",str=str},TypeMT)
  return types._opaque[str]
end

types._uint={}
function types.uint(prec)
  types._uint[prec] = types._uint[prec] or setmetatable({kind="uint",precision=prec},TypeMT)
  return types._uint[prec]
end

types._int={}
function types.int(prec)
  types._int[prec] = types._int[prec] or setmetatable({kind="int",precision=prec},TypeMT)
  return types._int[prec]
end

types._float={}
function types.float(prec)
  types._float[prec] = types._float[prec] or setmetatable({kind="float",precision=prec},TypeMT)
  return types._float[prec]
end

ShapeMT = {}
function types.isShape(w) return getmetatable(w)==ShapeMT end

types._shape = {}
function types.shapevar(varname, scale)
  assert(type(varname)=="string")
  assert(type(scale)=="number")
  local s = setmetatable({varname,scale}, ShapeMT)
  return deepsetweak( types._shape, s, s )
end

types._array={}

function types.array2d( _type, w, h )
  assert( types.isType(_type) )
  assert( type(w)=="number" or types.isShape(w))
  assert( type(h)=="number" or types.isShape(h) or h==nil)
  if h==nil then h=1 end -- by convention, 1d arrays are 2d arrays with height=1

  -- dedup the arrays
  local ty = setmetatable( {kind="array", over=_type, size={w,h}}, TypeMT )
  return deepsetweak(types._array, {_type,w,h}, ty)
end

types._tuples = {}

function types.tuple( list )
  if #list==1 and types.isType(list[1]) then return list[1] end
  list = map( list, function(n) assert( types.isType(n) ); return n end )
  types._tuples[#list] = types._tuples[#list] or {}
  local tup = setmetatable( {kind="tuple", list = list }, TypeMT )
  return deepsetweak( types._tuples, list, tup )
end

function types.fromTerraType(ty, linenumber, offset, filename)
  if types.isType(ty) then return ty end

  assert(terralib.types.istype(ty))

  if ty==int32 then
    return types.int(32)
  elseif ty==int16 then
    return types.int(16)
  elseif ty==uint8 then
    return types.uint(8)
  elseif ty==uint32 then
    return types.uint(32)
  elseif ty==int8 then
    return types.int(8)
  elseif ty==uint16 then
    return types.uint(16)
  elseif ty==float then
    return types.float(32)
  elseif ty==double then
    return types.float(64)
  elseif ty==bool then
    return types.bool()
  elseif ty:isarray() then
    if ty.N <=0 then
      darkroom.error("Array can not have size 0",linenumber,offset,filename)
    end
    return types.array(types.fromTerraType(ty.type),ty.N)
  end

  print("error, unsupported terra type",ty)
  assert(false)
end

-- given a lua variable, figure out the correct type and
-- least precision that can represent it
function types.valueToType(v)

  if v==nil then return nil end
  
  if type(v)=="boolean" then
    return types.bool()
  elseif type(v)=="number" then
    local vi, vf = math.modf(v) -- returns the integral bit, then the fractional bit
    
    -- you might be tempted to take things from 0...255 to a uint8 etc, but this is bad!
    -- then if the user write -(5+4) they get a positive number b/c it's a uint8!
    -- similarly, if you take -128...127 to a int8, you also get problems. Then, you
    -- try to meet this int8 with a uint8, and get a int16! (bc this is the only sensible thing)
    -- when really what you wanted is a uint8.
    -- much better to just make the default int32 and have users cast it to what they want
    
    if vf~=0 then
      return types.float(32)
    else
      return types.int(32)
    end
  elseif type(v)=="table" then
    if keycount(v)~=#v then return nil end
    local tys = {}
    for k,vv in ipairs(v) do
      tys[k] = types.valueToType(vv)
      if tys[k]==nil then return nil end
    end
    return types.array(types.reduce("",tys),#v)
  end
  
  return nil -- fail
end

-- returns resultType, lhsType, rhsType
-- ast is used for error reporting
function types.meet( a, b, op, ast)
  assert(types.isType(a))
  assert(types.isType(b))
  assert(type(op)=="string")
  assert(darkroom.IR.isIR(ast))
  
  assert(getmetatable(a)==TypeMT)
  assert(getmetatable(b)==TypeMT)

  local treatedAsBinops = {["select"]=1, ["vectorSelect"]=1,["array"]=1, ["mapreducevar"]=1, ["dot"]=1, ["min"]=1, ["max"]=1}

  if a:isArray() and b:isArray() then
    if a:arrayLength() ~= b:arrayLength() then
      print("Type error, array length mismatch")
      return nil
    end
    
    if op=="dot" then
      local rettype,at,bt = types.meet(a.over,b.over,op,ast)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      return rettype, convtypea, convtypeb
    elseif darkroom.cmpops[op] then
      -- cmp ops are elementwise
      local rettype,at,bt = types.meet(a.over,b.over,op,ast)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      
      local thistype = types.array( types.bool(), a:arrayLength() )
      return thistype, convtypea, convtypeb
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      -- do it pointwise
      local thistype = types.array( types.meet(a.over,b.over,op,ast), a:arrayLength() )
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.array(types.float(32), a:arrayLength() )
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
      
  elseif a.kind=="int" and b.kind=="int" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.int(prec)
    
    if darkroom.cmpops[op] then
      return types.bool(), thistype, thistype
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
  elseif a.kind=="uint" and b.kind=="uint" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.uint(prec)
    
    if darkroom.cmpops[op] then
      return types.bool(), thistype, thistype
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP2",op)
      assert(false)
    end
  elseif (a.kind=="uint" and b.kind=="int") or (a.kind=="int" and b.kind=="uint") then
    
    local ut = a
    local t = b
    if a.kind=="int" then ut,t = t,ut end
    
    local prec
    if ut.precision==t.precision and t.precision < 64 then
      prec = t.precision * 2
    elseif ut.precision<t.precision then
      prec = math.max(a.precision,b.precision)
    else
      darkroom.error("Can't meet a "..tostring(ut).." and a "..tostring(t),ast:linenumber(),ast:offset(),ast:filename())
    end
    
    local thistype = types.int(prec)
    
    if darkroom.cmpops[op] then
      return types.bool(), thistype, thistype
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      return thistype, thistype, thistype
    else
      print( "operation " .. op .. " is not implemented for aType:" .. a.kind .. " bType:" .. b.kind .. " " )
      assert(false)
    end
    
  elseif (a.kind=="float" and (b.kind=="uint" or b.kind=="int")) or 
    ((a.kind=="uint" or a.kind=="int") and b.kind=="float") then
    
    local thistype
    local ftype = a
    local itype = b
    if b.kind=="float" then ftype,itype=itype,ftype end
    
    if ftype.precision==32 and itype.precision<32 then
      thistype = types.float(32)
    elseif ftype.precision==32 and itype.precision==32 then
      thistype = types.float(32)
    elseif ftype.precision==64 and itype.precision<64 then
      thistype = types.float(64)
    else
      assert(false) -- NYI
    end
    
    if darkroom.cmpops[op] then
      return types.bool(), thistype, thistype
    elseif darkroom.intbinops[op] then
      darkroom.error("Passing a float to an integer binary op "..op,ast:linenumber(),ast:offset())
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP4",op)
      assert(false)
    end
    
  elseif a.kind=="float" and b.kind=="float" then
    
    local prec = math.max(a.precision,b.precision)
    local thistype = types.float(prec)
    
    if darkroom.cmpops[op] then
      return types.bool(), thistype, thistype
    elseif darkroom.intbinops[op] then
      darkroom.error("Passing a float to an integer binary op "..op,ast:linenumber(),ast:offset())
    elseif darkroom.binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP3",op)
      assert(false)
    end
    
  elseif a.kind=="bool" and b.kind=="bool" then
    -- you can combine two bools into an array of bools
    if darkroom.boolops[op]==nil and op~="array" then
      print("Internal error, attempting to meet two booleans on a non-boolean op: "..op,ast:linenumber(),ast:offset())
      return nil
    end
    
    local thistype = types.bool()
    return thistype, thistype, thistype
  elseif a:isArray() and b:isArray()==false then
    -- we take scalar constants and duplicate them out to meet the other arguments array length
    local thistype, lhstype, rhstype = types.meet( a, types.array( b,a :arrayLength() ), op, ast )
    return thistype, lhstype, rhstype
  elseif a:isArray()==false and b:isArray() then
    local thistype, lhstype, rhstype = types.meet( types.array(a, b:arrayLength() ), b, op, ast )
    return thistype, lhstype, rhstype
  else
    print("Type error, meet not implemented for "..tostring(a).." and "..tostring(b),"line",ast:linenumber(),ast:filename())
    print(ast.op)
    assert(false)
    --os.exit()
  end
  
  assert(false)
  return nil
end

-- convert a string describing a type like 'int8' to its actual type
function types.stringToType(s)
  if s=="rgb8" then
    local res = types.array(types.uint(8),3)
    assert(types.isType(res))
    return res
  elseif s=="rgbw8" then
    return types.array(types.uint(8),4)
  elseif s:sub(1,4) == "uint" then
    if s=="uint" then
      darkroom.error("'uint' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(5))==nil then return nil end
    return types.uint(tonumber(s:sub(5)))
  elseif s:sub(1,3) == "int" then
    if s=="int" then
      darkroom.error("'int' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(4))==nil then return nil end
    return types.int(tonumber(s:sub(4)))
  elseif s:sub(1,5) == "float" then
    if s=="float" then
      darkroom.error("'float' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(6))==nil then return nil end
    return types.float(tonumber(s:sub(6)))
  elseif s=="bool" then
    return types.bool()
  else

  end
 
  --print("Error, unknown type "..s)
  return nil
end

-- check if type 'from' can be converted to 'to' (explicitly)
function types.checkExplicitCast(from, to, ast)
  assert(from~=nil)
  assert(to~=nil)
  assert(darkroom.ast.isAST(ast))

  if from==to then
    -- obvously can return true...
    return true
  elseif from:isArray() and to:isArray() then
    -- we do allow you to explicitly cast arrays of different shapes but the same total size
    if from:channels()~=to:channels() then
      darkroom.error("Can't change array length when casting "..tostring(from).." to "..tostring(to), ast:linenumber(), ast:offset(), ast:filename() )
    end

    return types.checkExplicitCast(from.over, to.over,ast)

  elseif (from:isStruct()==false and from:isArray()==false) and to:isArray() then
    return types.checkExplicitCast(from, to.over, ast )

  elseif from:isArray() and (to:isArray()==false and to:isStruct()==false) then
    if from:arrayOver():isBool() and from:channels()==to:sizeof()*8 then
      -- casting an array of bools to a type with the same number of bits is OK
      return true
    elseif from:channels()==1 and types.checkExplicitCast(from:arrayOver(),to,ast) then
      -- can explicitly cast an array of size 1 to a compatible type
      return true
    end

    darkroom.error("Can't cast an array type to a non-array type. "..tostring(from).." to "..tostring(to), ast:linenumber(), ast:offset(), ast:filename() )
    return false
  elseif from:isStruct() and to:isStruct()==false and keycount(from.kvs)==1 then
    for k,v in pairs(from.kvs) do
      return types.checkExplicitCast(v,to,ast)
    end
  elseif from:isStruct() and to:isStruct() and keycount(from.kvs)==keycount(to.kvs) then
    for k,v in pairs(from.kvs) do
      if to.kvs[k]==nil then return false end
      if types.checkExplicitCast(v,to.kvs[k],ast)==false then return false end
    end
    return true
  elseif from.kind=="uint" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="int" then
    return true
  elseif from.kind=="uint" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="uint" then
    return true
  elseif from.kind=="uint" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="bool" then
    darkroom.error("converting an int to a bool will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="bool" and (to.kind=="int" or to.kind=="uint") then
    darkroom.error("converting a bool to an int will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="float" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="float" then
    return true
  else
    print(from,to)
    assert(false) -- NYI
  end

  return false
end

-- compare this to meet - this is where we can't change the type of 'to',
-- so we just have to see if 'from' can be converted to 'to'
function types.checkImplicitCast(from, to, ast)
  assert(types.isType(from))
  assert(types.isType(to))
  assert(darkroom.IR.isIR(ast))

  if from==to then
    return true -- obviously
  elseif from.kind=="uint" and to.kind=="uint" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.kind=="uint" and to.kind=="int" then
    if to.precision > from.precision then
      return true
    end
  elseif from.kind=="int" and to.kind=="int" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.kind=="uint" and to.kind=="float" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.kind=="int" and to.kind=="float" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.kind=="float" and to.kind=="float" then
    if to.precision >= from.precision then
      return true
    end
  elseif from:isStruct() and to:isStruct()==false and keycount(from.kvs)==1 then
    -- convert a struct of one entry to the type of that entry
    -- terrible, terrible language design
    for k,v in pairs(from.kvs) do
      return types.checkImplicitCast(v,to,ast)
    end
  elseif from:isStruct() and to:isStruct() and keycount(from.kvs)==keycount(to.kvs) then
    for k,v in pairs(from.kvs) do
      if to.kvs[k]==nil then print("A");return false end
      local r = types.checkImplicitCast(v,to.kvs[k],ast)
      if r==false then return false end
    end
    return true
  end

  return false
end

---------------------------------------------------------------------
-- 'externally exposed' functions

function types.isType(ty)
  return getmetatable(ty)==TypeMT
end

-- convert this uint type to an int type with same precision
function types.uintToInt(ty)
  assert(types.isUint(ty))
  return types.int(ty.precision)
end

function TypeFunctions:toC()
  if self.kind=="float" and self.precision==32 then
    return "float"
  elseif self.kind=="uint" and self.precision==8 then
    return "unsigned char"
  elseif self.kind=="int" and self.precision==32 then
    return "int"
  elseif self:isArray() then
    return self:baseType():toC().."["..self:channels().."]"
  else
    print(self)
    assert(false)
  end
end

function TypeFunctions:isArray()  return self.kind=="array" end
function TypeFunctions:isTuple()  return self.kind=="tuple" end

function TypeFunctions:arrayOver()
  assert(self.kind=="array")
  return self.over
end

-- returns 0 if not an array
function TypeFunctions:arrayLength()
  if self.kind~="array" then return 0 end
  return self.size
end

function TypeFunctions:tupleList()
  if self.kind~="tuple" then return {self} end
  return self.list
end

-- if pointer is true, generate a pointer instead of a value
-- vectorN = width of the vector [optional]
function TypeFunctions:toTerraType(pointer, vectorN)
  local ttype

  if self==types.float(32) then
    ttype = float
  elseif self==types.float(64) then
    ttype = double
  elseif self==types.uint(8) then
    ttype = uint8
  elseif self==types.int(8) then
    ttype = int8
  elseif self==types.bool() then
    ttype = bool
  elseif self==types.int(32) then
    ttype = int32
  elseif self==types.int(64) then
    ttype = int64
  elseif self==types.uint(32) then
    ttype = uint32
  elseif self==types.uint(16) then
    ttype = uint16
  elseif self==types.int(16) then
    ttype = int16
  elseif self:isArray() then
    assert(vectorN==nil)
    ttype = (self.over:toTerraType())[self:channels()]
  elseif self.kind=="tuple" then
    ttype = tuple( unpack(map(self.list, function(n) return n:toTerraType(pointer, vectorN) end)) )
  elseif self.kind=="opaque" then
    ttype = &opaque
  else
    print(self)
    print(debug.traceback())
    assert(false)
  end

  if vectorN then
    if pointer then return &vector(ttype,vectorN) end
    return vector(ttype,vectorN)
  else
    if pointer then return &ttype end
    return ttype
  end

  print(types.typeToString(_type))
  assert(false)

  return nil
end

function TypeFunctions:sizeof()
  return terralib.sizeof(self:toTerraType())
end

function TypeFunctions:isFloat()
  return self.kind=="float"
end

function TypeFunctions:isBool()
  return self.kind=="bool"
end

function TypeFunctions:isInt()
  return self.kind=="int"
end

function TypeFunctions:isUint()
  return self.kind=="uint"
end

function TypeFunctions:isStruct()
  return self.kind=="struct"
end

function TypeFunctions:isNumber()
  return self.kind=="float" or self.kind=="uint" or self.kind=="int"
end

function TypeFunctions:channels()
  if self.kind~="array" then return 1 end
  local chan = 1
  for k,v in ipairs(self.size) do chan = chan*v end
  return chan
end

function TypeFunctions:baseType()
  if self.kind~="array" then return self end
  assert(type(self.over)~="array")
  return self.over
end

-- this calculates the precision of the result of a reduction tree.
-- op is the reduction op
-- typeTable is a list of the types we're reducing over
function types.reduce(op,typeTable)
  assert(type(typeTable)=="table")
  assert(#typeTable>=1)
  for k,v in pairs(typeTable) do assert(types.isType(v)) end

  return typeTable[1]
end

return types