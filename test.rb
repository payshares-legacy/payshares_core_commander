require 'payshares_core_commander'
require 'pry'

bin = File.expand_path("~/src/payshares/payshares-core/bin/payshares-core")
cmd = PaysharesCoreCommander::Commander.new(bin)

cmd.cleanup_at_exit!
p1 = cmd.make_process


binding.pry