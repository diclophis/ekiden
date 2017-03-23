require 'resque'
require 'resque-lonely_job'

class Marvin
  extend Resque::Plugins::LonelyJob

  def self.reset_work(integration_id)
    Resque.redis.multi do |multi|
      multi.del(set_name_for_processed_events(integration_id))
      multi.del(set_name_for_all_events(integration_id))
      multi.del(set_name_for_tmp_sorted_events(integration_id))
    end
  end

  def self.base_make_work(worker_class, integration_id, event = nil)
    if event
      Resque.redis.zadd(set_name_for_all_events(integration_id), Time.now.to_f, event)
    end
    Resque.enqueue(worker_class, integration_id)
  end

  def self.handle_signal(signal, integration_id)
    case Signal.signame(signal.signo)
      when "INT", "TERM"
        reenqueue(integration_id)
        exit 1
    end
  end

  def self.set_name_for_all_events(integration_id)
    ["all_events", integration_id].join(":")
  end

  def self.set_name_for_processed_events(integration_id)
    ["processed_events", integration_id].join(":")
  end

  def self.set_name_for_tmp_sorted_events(integration_id)
    ["tmp_events", integration_id].join(":")
  end

  def self.redis_key(integration_id)
    "worker:mutex:#{integration_id}"
  end

  def self.work_on(integration_id, event)
    log ["NULL-IMPL", integration_id, event]
  end

  def self.perform(integration_id)
    log [:scanning_work_for, integration_id]

    # ZUNIONSTORE tmp 2 all processed WEIGHTS 1 0 AGGREGATE MIN
    # zunionstore(destination, keys, options = {}) ⇒ Fixnum
    Resque.redis.zunionstore(set_name_for_tmp_sorted_events(integration_id), [
      set_name_for_all_events(integration_id),
      set_name_for_processed_events(integration_id)
    ], {:weights => [1, 0], :aggregate => "min"})

    # ZREVRANGEBYSCORE tmp +inf 1 WITHSCORES
    # zrevrangebyscore(key, max, min, options = {}) ⇒ Object
    range = Resque.redis.zrevrangebyscore(set_name_for_tmp_sorted_events(integration_id), "+inf", 1, {:with_scores => true})
    remaining_work_range = range.reverse
    if remaining_work_range.length > 0
      log [:performing_work_for, integration_id]
      remaining_work_range.each do |event, score|
        if self.work_on(integration_id, event)
          Resque.redis.zadd(set_name_for_processed_events(integration_id), score, event)
        end
      end
    else
      log [:skipping_work_for, integration_id, "no remaining work, likely duplicate events"]
    end
  rescue Resque::TermException, SignalException => signal
    self.handle_signal(signal, integration_id)
  end

  def self.log(args)
    puts args.inspect
  end
end
