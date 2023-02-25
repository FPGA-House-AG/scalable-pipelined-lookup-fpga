# Scalable Pipelined Lookup (FPGA)

**Work in progress!**

SpinalHDL rewrite of SystemVerilog implementation of the scalable pipelined
lookup.

## If it is your are learning SpinalHDL

You can follow the tutorial on the [Getting Started] page.

More specifically:

* instructions to install tools can be found on the [Install and setup] page,
* instructions to get this repository locally are available in the [Create a
  SpinalHDL project] section.


### TL;DR Things have arleady been set up in my environment, how do I run things to try SpinalHDL?

Once in the `scalable-pipelined-lookup-fpga` directory, when tools are
installed, the commands below can be run to use `sbt`.

```sh
// To generate the Verilog from the example
sbt "runMain scalablePipelinedLookup.LookupTopVerilog"

// To generate the VHDL from the example
sbt "runMain scalablePipelinedLookup.LookupTopVVhdl"

// To run the testbench
sbt "runMain scalablePipelinedLookup.LookupTopVSim"
```

When you really start working with SpinalHDL, it is recommended (both for
comfort and efficiency) to use an IDE, see the [Getting started].

[Getting started]: https://spinalhdl.github.io/SpinalDoc-RTD/master/SpinalHDL/Getting%20Started/index.html
[Install and setup]: https://spinalhdl.github.io/SpinalDoc-RTD/master/SpinalHDL/Getting%20Started/Install%20and%20setup.html#install-and-setup
[Create a SpinalHDL project]:
    https://spinalhdl.github.io/SpinalDoc-RTD/master/SpinalHDL/Getting%20Started/Install%20and%20setup.html#create-a-spinalhdl-project
