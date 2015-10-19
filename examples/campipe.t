local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local f = require "fixed"
local modules = require "fpgamodules"
local C = require "examplescommon"

W = 512
H = 512
T = 8

----------------
function blackLevel( pedestal )
  local blackLevelInput = f.parameter("blInput",types.uint(8))
  local bli = blackLevelInput:lift(0)
  local res = 128*(255/(255-pedestal))
  print("RESCALE",res)
  local rescale = f.constant(res,false,8,-7)
  local out = (bli:toSigned()-f.constant(pedestal,false,8,0):toSigned())*rescale:toSigned()
  out = out:abs():denormalize()
  local a = f.constant(255,false,out:precision(),0)
  print(a.type,out.type)
  out = f.select(out:gt(f.constant(255,false,8)),a,out)
  return out:truncate(8):lower():toDarkroom("blackLevel")
end

function demosaic(inputType)
  -- BG
  -- GR

  local r_tl = {1,0,1,
                0,0,0,
                1,0,1}
  local r_tr = {0,2,0,
                0,0,0,
                0,2,0}
  local r_bl = {0,0,0,
                2,0,2,
                0,0,0}
  local r_br = {0,0,0,
                0,4,0,
                0,0,0}
  local r = {r_bl,r_br,r_tl,r_tr}

  local g_tl = {0,1,0,
                1,0,1,
                0,1,0}
  local g_tr = {0,0,0,
                0,4,0,
                0,0,0}
  local g_bl = {0,0,0,
                0,4,0,
                0,0,0}
  local g_br = {0,1,0,
                1,0,1,
                0,1,0}
  local g = {g_bl,g_br,g_tl,g_tr}

  local b_tl = {0,0,0,
                0,4,0,
                0,0,0}
  local b_tr = {0,0,0,
                2,0,2,
                0,0,0}
  local b_bl = {0,2,0,
                0,0,0,
                0,2,0}
  local b_br = {1,0,1,
                0,0,0,
                1,0,1}
  local b = {b_bl,b_br,b_tl,b_tr}

  local kerns = {r,g,b}

  -----------
  local function KSI(tab,name,phaseX,phaseY)
    local ITYPE = types.tuple{types.uint(16),types.uint(16)}
    local kernelSelectInput = S.parameter("ksi",ITYPE)

    local x = S.cast(S.index(kernelSelectInput,0),types.uint(16))
    x = S.__and(x,S.constant(3,types.uint(16)))
    local y = S.cast(S.index(kernelSelectInput,1),types.uint(16))
    y = S.__and(y,S.constant(3,types.uint(16)))
    local x = x + S.constant(phaseX,types.uint(16))
    local y = y + S.constant(phaseY,types.uint(16))
    local phase = x+(y*S.constant(2,types.uint(16)))

    local tt = {}
    local ATYPE = types.array2d(types.uint(8),3,3)
    for k,v in ipairs(tab) do table.insert(tt,S.constant(v,ATYPE)) end
    local kernelSelectOut = modules.wideMux( tt, phase )
    return darkroom.lift(name, ITYPE, ATYPE, 5,
                         terra(inp:&tuple(uint16,uint16),out:&uint8[9])
                           var x,y = inp._0,inp._1
                           var phase = ((x+phaseX)%2)+((y+phaseY)%2)*2
                           var ot : int32[9]
                           if phase==0 then ot = array([tab[1]])
                           elseif phase==1 then ot = array([tab[2]])
                           elseif phase==2 then ot = array([tab[3]])
                           else ot = array([tab[4]]) end
                           for i=0,9 do (@out)[i] = ot[i] end
                         end, kernelSelectInput, kernelSelectOut)
  end
  -----------

  local XYTYPE = types.tuple{types.uint(16),types.uint(16)}
  local DTYPE = types.tuple{XYTYPE,types.array2d(types.uint(8),3,3)}
  local deminp = d.input(DTYPE)
  local xy = d.apply("xy",d.index(DTYPE,0),deminp)
  local st = d.apply("dat",d.index(DTYPE,1),deminp)

  local phaseX,phaseY=1,0

  local out = {}
  for i=1,3 do
    local kern = d.apply("k"..i,KSI(kerns[i],"kern"..i,phaseX,phaseY),xy)

    local ConvWidth = 3
    local A = types.uint(8)
    local packed = d.apply( "packedtup"..i, d.SoAtoAoS(ConvWidth,ConvWidth,{A,A}), d.tuple("ptup"..i, {st,kern}) )
    local conv = d.apply( "partialll"..i, d.map( C.multiply(A,A,types.uint(16)), ConvWidth, ConvWidth ), packed )
    local conv = d.apply( "sum"..i, d.reduce( C.sum(types.uint(16),types.uint(16),types.uint(16)), ConvWidth, ConvWidth ), conv )
    local conv = d.apply( "touint8"..i, C.shiftAndCastSaturate( types.uint(16), A, 2 ), conv )

    out[i] = conv
  end

  local dem = d.lambda("dem", deminp, d.array2d("ot",out,3))
  dem = darkroom.liftXYSeqPointwise(dem,W,H,T)

  ---------------
  local demtop = d.input(types.array2d(types.uint(8),T))
  local st = d.apply( "st", d.stencilLinebuffer(types.uint(8),W,H,T,-2,0,-2,0), demtop)
  local st = d.apply( "convstencils", d.unpackStencil( types.uint(8), 3, 3, T ) , st )
  local demtopout = d.apply("dem",dem,st)

  return d.lambda("demtop",demtop,demtopout)
end

ccmtab={ {255/142,0,0},
{0, 196/255, 0},
{0,0,1}}

function makeCCM(tab)
  local ccminp = f.parameter("ccminp",types.array2d(types.uint(8),3))
  local out = {}
  for c=1,3 do
    out[c] = f.constant(tab[c][1]*128,false,8,-7)*ccminp:index(0):lift(0)
    for i=2,3 do
      out[c] = out[c] + f.constant(tab[c][i]*128,false,8,-7)*ccminp:index(i-1):lift(0)
    end
    out[c] = out[c]:denormalize()
    local a = f.constant(255,false,out[c]:precision(),0)
    out[c] = f.select(out[c]:gt(f.constant(255,false,8)),a,out[c])
    out[c] = out[c]:truncate(8):lower()
  end

  local res = f.array2d(out,3)
  return res:toDarkroom("ccm")
end

function addchan()
  local inp = f.parameter("inp",types.array2d(types.uint(8),3))
  local out={}
  for c=0,2 do
    out[c] = inp:index(c)
  end
  out[3] = f.plainconstant(0,types.uint(8))
  return f.array2d(out,4):toDarkroom("addChan")
end

local function makeGamma(g)
  local gamma = {}
  for i=0,255 do table.insert(gamma, math.pow(i/255,g)*255) end
  return gamma
end

local ITYPE = types.array2d(types.uint(8),T)
local rgbType = types.array2d(types.uint(8),4)
local OTYPE = types.array2d(rgbType,2)

local inp = d.input(ITYPE)
local bl = d.apply("bl",d.map(blackLevel(10),T),inp)
local dem = d.apply("dem",demosaic(),bl)
local ccm = d.apply("ccm",d.map(makeCCM(ccmtab),T),dem)
local gam = d.apply("gam",d.map(d.map(d.lut(types.uint(8),types.uint(8),makeGamma(1/2.4)),3),T),ccm)
local out = d.apply("addchan",d.map(addchan(),T),gam)
--local dem = d.apply("fake",d.map(C.arrayop(types.uint(8),4),T),bl)
local campipe = d.lambda("campipe",inp,out)

local hsfninp = d.input(d.Handshake(ITYPE))
local hsfnout = d.apply("O1",d.makeHandshake(campipe),hsfninp)
local hsfnout = d.apply("incrate", d.liftHandshake(d.changeRate(rgbType,1,T,2)), hsfnout )
local hsfn = d.lambda("hsfn",hsfninp,hsfnout)

harness.axi( "campipe", hsfn, "300d_w512_h512.raw", nil, nil, ITYPE, T,W,H, OTYPE,2,W,H)