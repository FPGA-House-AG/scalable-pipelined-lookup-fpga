package scalablePipelinedLookup

import spinal.core._
import spinal.core.sim._

object LookupTopSim extends App {
  Config.sim.compile(LookupTop()).doSim { dut =>
    // Fork a process to generate the reset and the clock on the dut
    dut.clockDomain.forkStimulus(period = 10)

    /** Update request. */
    def update(
        valid: Boolean,
        ipAddr: Long,
        length: Int,
        stageId: Int,
        location: Int,
        childStageId: Int,
        childLocation: Int,
        childHasLeft: Boolean,
        childHasRight: Boolean
    ): Unit = {
      dut.io.update.update #= valid
      dut.io.update.ipAddr #= ipAddr
      dut.io.update.bitPos #= length
      dut.io.update.stageId #= stageId
      dut.io.update.location #= location
      dut.io.update.child.stageId #= childStageId
      dut.io.update.child.location #= childLocation
      dut.io.update.child.childLr.hasLeft #= childHasLeft
      dut.io.update.child.childLr.hasRight #= childHasRight

      if (valid) {
        println(
          "Requesting update for "
            + f"IP=0x$ipAddr%x/$length, stage=$stageId, loc=0x$location%x "
            + f"for child: stage=$childStageId, loc=0x$childLocation%x, "
            + s"l/r=$childHasLeft/$childHasRight."
        )
        var counter = 0
        dut.clockDomain.onSamplingWhile {
          counter += 1
          assert(
            counter < 2 || dut.io.updateAck.toBoolean == true,
            "Update request should be ackowledged."
          )
          counter == 2
        }
      }
    }

    /** Latency from lookup request to result. */
    val Latency = dut.config.ipAddrWidth * 2 + 1

    /** Cycle on which a lookup is perormed. */
    val LookupCycle = 6

    /** Count of cycles to simulate. */
    val Cycles = Latency + LookupCycle

    /** Request IP cache used for result check. */
    val requestIpCache = Array.fill(2)(Array.fill(Cycles)(BigInt(0)))

    for (i <- 0 until Cycles) {
      // Set defaults.
      dut.io.lookup.foreach(lookup => {
        lookup.payload #= 0
        lookup.valid #= false
      })
      update(false, 0, 0, 0, 0, 0, 0, false, false)

      i match {
        case 1 => {
          // Request update.
          update(true, 0x327b23c0L, 24, 3, 1, 0x3c, 0x123, false, false)
        }
        case LookupCycle => {
          // Request lookup on both channels.
          dut.io.lookup(0).valid #= true
          dut.io.lookup(0).payload #= 0x327b23f0L

          dut.io.lookup(1).valid #= true
          dut.io.lookup(1).payload #= 0x62555800L
        }
        case _ => {}
      }

      dut.clockDomain.waitSampling()

      // Populate lookup cache.
      for ((cache, dutLookup) <- requestIpCache zip dut.io.lookup) {
        cache(i) = dutLookup.payload.toBigInt
      }

      // Present lookup result with latency taken into account.
      if (i >= Latency) {
        val inOut = requestIpCache.zip(dut.io.result).map { case (cache, result) =>
          (f"0x${cache(i - Latency + 1)}%08x -> "
            + f"stage=${result.lookupResult.stageId.toInt}%02d "
            + f"loc=0x${result.lookupResult.location.toInt}%04x "
            + s"l/r=${result.lookupResult.childLr.hasLeft.toBigInt}/"
            + s"${result.lookupResult.childLr.hasRight.toBigInt}")
        }
        println(s"Cycle $i: ${inOut(0)}, ${inOut(1)}")
      }
    }
  }
}
