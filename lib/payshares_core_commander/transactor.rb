require 'fileutils'
module PaysharesCoreCommander


  # 
  # A transactor plays transactions against a payshares-core test node.
  # 
  # 
  class Transactor
    include Contracts

    class FailedTransaction < StandardError ; end

    Currency = [String, Symbol]
    Amount = Any #TODO

    OfferCurrencies = Or[
      {sell:Currency, for: Currency},
      {buy:Currency, with: Currency},
    ]

    Contract Process => Any
    def initialize(process)
      @process    = process
      @named      = {}.with_indifferent_access
      @unverified = []
      account :master, Payshares::KeyPair.from_raw_seed("allmylifemyhearthasbeensearching")
    end

    Contract String => Any

    # 
    # Runs the provided recipe against the process identified by @process
    # 
    # @param recipe_path [String] path to the recipe file
    # 
    def run_recipe(recipe_path)
      raise "payshares-core not running" unless @process.running? 

      recipe_content = IO.read(recipe_path)
      instance_eval recipe_content
    end


    Contract Symbol, Payshares::KeyPair => Any
    # 
    # Registered an account for this scenario.  Future calls may refer to
    # the name provided.
    # 
    # @param name [Symbol] the name to register the keypair at
    # @param keypair=Payshares::KeyPair.random [Payshares::KeyPair] the keypair to use for this account
    # 
    def account(name, keypair=Payshares::KeyPair.random)
      unless keypair.is_a?(Payshares::KeyPair)
        raise ArgumentError, "`#{keypair.class.name}` is not `Payshares::KeyPair`"
      end

      add_named name, keypair
    end

    Contract Symbol, Symbol, Amount, Or[{}, {path: Any}] => Any
    def payment(from, to, amount, options={})
      from = get_account from
      to   = get_account to

      if amount.first != :native
        amount    = [:iso4217] + amount
        amount[2] = get_account(amount[2])
        amount[1] = amount[1].ljust(4, "\x00")
      end

      attrs = {
        account:     from,
        destination: to,
        sequence:    next_sequence(from),
        amount:      amount,
      }

      if options[:path]
        attrs[:path] = options[:path].map{|p| make_currency p}
      end
      envelope = Payshares::Transaction.payment(attrs).to_envelope(from)

      submit_transaction envelope do |result|
        payment_result = result.result.results!.first.tr!.payment_result!

        raise FailedTransaction unless payment_result.code.value >= 0
      end
    end

    Contract Symbol, Symbol, String => Any
    def trust(account, issuer, code)
      change_trust account, issuer, code, (2**63)-1
    end    

    Contract Symbol, Symbol, String, Num => Any
    def change_trust(account, issuer, code, limit)
      account = get_account account

      tx = Payshares::Transaction.change_trust({
        account:  account,
        sequence: next_sequence(account),
        line:     make_currency([code, issuer]),
        limit:    limit
      })

      envelope = tx.to_envelope(account)

      submit_transaction envelope
    end



    Contract Symbol, Symbol, OfferCurrencies, Num, Num => Any
    def offer(name, account, currencies, amount, price)
      account    = get_account account

      if currencies.has_key?(:sell)
        taker_pays = make_currency currencies[:for]
        taker_gets = make_currency currencies[:sell]
      else
        taker_pays = make_currency currencies[:buy]
        taker_gets = make_currency currencies[:with]
      end

      tx = Payshares::Transaction.create_offer({
        account:  account,
        sequence: next_sequence(account),
        taker_gets: taker_gets,
        taker_pays: taker_pays,
        amount: amount,
        price: price,
      })
      
      envelope = tx.to_envelope(account)

      submit_transaction envelope do |result|
        offer = begin
          co_result = result.result.results!.first.tr!.create_offer_result!
          co_result.success!.offer.offer!
        rescue
          raise FailedTransaction, "Could not extract offer from result:#{result.to_xdr(:base64)}"
        end

        add_named name, offer
      end
    end

    Contract None => Any
    # 
    # Triggers a ledger close.  Any unvalidated transaction will
    # be validated, which will trigger an error if any fail to be validated
    # 
    def close_ledger
      @process.close_ledger

      @unverified.each do |eb|
        begin
          envelope, after_confirmation = *eb
          result = validate_transaction envelope
          after_confirmation.call(result) if after_confirmation
        rescue FailedTransaction
          $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
          $stderr.puts "failed result: #{result.to_xdr(:hex)}"
          exit 1
        end
      end

      # TODO: validate in-flight transactions
      @unverified.clear
    end

    private
    Contract Symbol, Any => Any
    def add_named(name, object)
      if @named.has_key?(name)
        raise ArgumentError, "#{name} is already registered"
      end

      @named[name] = object
    end

    Contract Payshares::TransactionEnvelope, Or[nil, Proc] => Any
    def submit_transaction(envelope, &after_confirmation)
      hex    = envelope.to_xdr(:hex)
      @process.submit_transaction hex

      # submit to process
      @unverified << [envelope, after_confirmation]
    end

    Contract Symbol => Payshares::KeyPair
    def get_account(name)
      @named[name].tap do |found|
        unless found.is_a?(Payshares::KeyPair)
          raise ArgumentError, "#{name.inspect} is not account"
        end
      end
    end

    Contract Payshares::KeyPair => Num
    def next_sequence(account)
      base_sequence  = @process.sequence_for(account)
      inflight_count = @unverified.select{|e| e.first.tx.source_account == account.public_key}.length
      
      base_sequence + inflight_count + 1
    end

    Contract Currency => [Symbol, String, Payshares::KeyPair]
    def make_currency(input)
      code, issuer = *input
      code = code.ljust(4, "\x00")
      issuer = get_account issuer

      [:iso4217, code, issuer]
    end

    Contract Payshares::TransactionEnvelope => Payshares::TransactionResult
    def validate_transaction(envelope)
      raw_hash = envelope.tx.hash
      hex_hash = Convert.to_hex(raw_hash)

      base64_result = @process.transaction_result(hex_hash)
      
      raise "couldn't fine result for #{hex_hash}" if base64_result.blank?
      
      raw_result = Convert.from_base64(base64_result)

      pair = Payshares::TransactionResultPair.from_xdr(raw_result)
      pair.result
    end

  end
end