local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
types.export()
local SDF = require "sdf"
local Zynq = require "zynq"

local regs = SOC.axiRegs({},SDF{1,128*64}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),0,noc.read}(i)
    local rs = G.FanOut{2}(readStream)
    local rs0 = G.FIFO{128}(rs[0])
    local rs1 = G.FIFO{128}(rs[1])
    local filt = G.HS{G.GT{192}}(rs1)
    print("FILT",filt.type)
    local finp = G.FanIn(rs0,filt)

    -- 368
    local offset = G.HS{G.FilterSeq{{368,8192}}}(finp)

    return G.AXIWriteBurstSeq{"out/soc_filterseq",{368,1},0,noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
