require 'fileutils'
module PaysharesCoreCommander
  class Commander
    include Contracts

    # 
    # Creates a new core commander
    # 
    Contract String => Any
    def initialize(payshares_core_bin)
      @payshares_core_bin = payshares_core_bin
      raise "no file at #{payshares_core_bin}" unless File.exist?(payshares_core_bin)

      @processes = []
    end

    Contract None => Process
    def make_process
      tmpdir = Dir.mktmpdir("pcc")

      identity      = Payshares::KeyPair.random
      base_port     = 39132 + (@processes.length * 2)

      FileUtils.cp(@payshares_core_bin, "#{tmpdir}/payshares-core")
      Process.new(tmpdir, base_port, identity).tap do |p|
        p.setup
        @processes << p
      end
    end

    def cleanup
      @processes.each(&:cleanup)
    end

    def cleanup_at_exit!
      at_exit do
        $stderr.puts "cleaning up #{@processes.length} processes"
        cleanup
      end
    end

  end
end