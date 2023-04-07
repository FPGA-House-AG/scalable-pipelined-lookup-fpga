package scalablePipelinedLookup

import scala.io.AnsiColor

import spinal.core._
import spinal.core.sim._
import spinal.lib.bus.amba4.axilite.sim.AxiLite4Driver

object LookupTopSim extends App {
  Config.sim.compile(LookupTop()).doSim { dut =>
    // Fork a process to generate the reset and the clock on the dut
    dut.clockDomain.forkStimulus(period = 10)
    val axiDriver = new AxiLite4Driver(dut.io.axi, dut.clockDomain)

    /** Update request. */
    def update(
        ipAddr: Long,
        length: Int,
        stageId: Int,
        location: Int,
        childStageId: Int,
        childLocation: Int,
        childHasLeft: Boolean,
        childHasRight: Boolean
    ): Unit = {
      SpinalInfo(
        "Requesting update for "
          + f"IP=0x$ipAddr%x/$length, stage=$stageId, loc=0x$location%x "
          + f"for child: stage=$childStageId, loc=0x$childLocation%x, "
          + s"l/r=$childHasLeft/$childHasRight."
      )

      assert(
        axiDriver.read(dut.AxiAddress.UPDATE_STATUS) == 0,
        "Update cannot be pending before starting a new one."
      )

      axiDriver.write(dut.AxiAddress.UDPATE_ADDR, (location << 16) | stageId)
      axiDriver.write(dut.AxiAddress.UPDATE_PREFIX, ipAddr)
      axiDriver.write(dut.AxiAddress.UPDATE_PREFIX_INFO, length)
      axiDriver.write(
        dut.AxiAddress.UPDATE_CHILD,
        (childHasLeft.toInt << 25) | (childHasRight.toInt << 24) | (childLocation << 8) | childStageId
      )

      axiDriver.write(dut.AxiAddress.UPDATE_COMMAND, 0)
    }

    SpinalInfo("TEST 1: See if lookup blocks update.")

    // Block the update by requesting lookup.
    dut.io.lookup.foreach(lookup => {
      lookup.payload #= 0
      lookup.valid #= true
    })
    dut.clockDomain.waitSampling()

    // Try to update.
    update(0x327b23c0L, 24, 3, 1, 0x3c, 0x123, false, false)
    assert(
      axiDriver.read(dut.AxiAddress.UPDATE_STATUS) == 1,
      "Update should be blocked during lookup."
    )

    // Unblock the update.
    dut.io.lookup.foreach(lookup => {
      lookup.payload #= 0
      lookup.valid #= false
    })

    SpinalInfo("TEST 2: Lookup on both channels.")

    /** Latency from lookup request to result. */
    val Latency = dut.config.ipAddrWidth * 2 + 1

    /** Cycle on which a lookup will be perormed. */
    val LookupCycle = 1

    /** Count of cycles to simulate. */
    val Cycles = Latency + LookupCycle + 2

    /** Request IP cache used for result check.
      *
      * First is the IP address which is looked up. Second is the information if
      * it is valid.
      */
    val requestIpCache = Array.fill(2)(Array.fill(Cycles)(BigInt(0), false))

    for (i <- 0 until Cycles) {
      // Set defaults.
      dut.io.lookup.foreach(lookup => {
        lookup.payload #= 0
        lookup.valid #= false
      })

      if (i == LookupCycle) {
        // Request lookup on both channels.
        dut.io.lookup(0).valid #= true
        dut.io.lookup(0).payload #= 0x327b23f0L

        dut.io.lookup(1).valid #= true
        dut.io.lookup(1).payload #= 0x62555800L
      }


      // Populate lookup cache.
      for ((cache, dutLookup) <- requestIpCache zip dut.io.lookup) {
        cache(i) = (dutLookup.payload.toBigInt, dutLookup.valid.toBoolean)
      }

      // Present lookup result with latency taken into account.
      if (i >= Latency) {
        val inOut = requestIpCache
          .zip(dut.io.result)
          .map { case (cache, result) =>
            ((if (cache(i - Latency + 1)._2) AnsiColor.GREEN else AnsiColor.RED)
              + f"0x${cache(i - Latency + 1)._1}%08x -> "
              + f"stage=${result.lookupResult.stageId.toInt}%02d "
              + f"loc=0x${result.lookupResult.location.toInt}%04x "
              + s"l/r=${result.lookupResult.childLr.hasLeft.toBigInt}/"
              + s"${result.lookupResult.childLr.hasRight.toBigInt}"
              + AnsiColor.RESET)
          }
        println(s"Cycle $i: ${inOut(0)}, ${inOut(1)}")
      }

      dut.clockDomain.waitSampling()
    }
  }
}
