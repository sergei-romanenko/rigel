local R = require "rigel"
R.export()
require "generators".export()
local harness = require "harnessSOC"
local SOC = require "soc"
local C = require "examplescommon"
local SDF = require "sdf"
require "types".export()
local Zynq = require "zynq"

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local W,H = 128,64

AddrGen = Module{SDF{1,1},function(inp)
  local x, y = Index{0}(Index{0}(inp)), Index{1}(Index{0}(inp))
  local resx = AddMSBs{16}(x)
  local resy = Mul( Sub(c(H-1,u(32)),AddMSBs{16}(y)),c(W/8,u(32)) )
  return Add(resx,resy)
end}

fn = Module{"Top",
  function(inp)
    local o = regs.start(inp)
    o = SOC.readBurst("frame_128.raw",128,64,u(8),8,nil,nil,noc.read)(o)

    local ob = FanOut{2}(o)
    local ob0 = R.selectStream("ob0",ob,0)
    print("OB0TYPE",ob0.type)
    ob0 = FIFO{128}(ob0)
    local ob1 = R.selectStream("ob1",ob,1)
    ob1 = FIFO{128}(ob1)
    ob1 = HS{ValueToTrigger}(ob1)
    local posSeqOut = HS{ PosSeq{{W/8,H},1} }(ob1)
    local addrGenOut = HS{AddrGen}(posSeqOut)

    local WRITEMOD = SOC.write("out/soc_flipWrite",128,64,u(8),8,nil,noc.write)
    print("WRITEMOD",WRITEMOD.inputType)
    print("OB0type",ob0.type)
    o = WRITEMOD(addrGenOut,ob0)
    o = TriggerCounter{(W*H)/8}(o)
    o = regs.done(o)
    return o
  end,{regs}}

harness(fn)
