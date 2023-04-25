package scalablePipelinedLookup

import spinal.core._
import spinal.lib._

/** Bundle representing a lookup result. */
case class LookupResult(config: LookupDataConfig) extends Bundle {

  /** IP address associated with the result. */
  val ipAddr = config.IpAddr()

  /** Last pipeline stage output. */
  val lookupResult = LookupChildBundle(config)
}
