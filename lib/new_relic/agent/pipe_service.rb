# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class PipeService
      attr_reader :channel_id, :buffer, :pipe
      attr_accessor :request_timeout, :agent_id, :collector

      MARSHAL_CHECK_FILENAME = '/tmp/f4b961bb.marshal_check_file'

      def initialize(channel_id)
        @channel_id = channel_id
        @collector = NewRelic::Control::Server.new(:name => 'parent',
                                                   :port => 0)
        @pipe = NewRelic::Agent::PipeChannelManager.channels[@channel_id]
        if @pipe && @pipe.parent_pid != $$
          @pipe.after_fork_in_child
        else
          NewRelic::Agent.logger.error("No communication channel to parent process, please see https://newrelic.com/docs/ruby/resque-instrumentation for more information.")
        end
      end

      def connect(config)
        nil
      end

      def get_agent_commands
        []
      end

      def analytic_event_data(events)
        write_to_pipe(:analytic_event_data, events) if events
      end

      def custom_event_data(events)
        write_to_pipe(:custom_event_data, events) if events
      end

      def metric_data(unsent_timeslice_data)
        write_to_pipe(:metric_data, unsent_timeslice_data)
        {}
      end

      def transaction_sample_data(transactions)
        write_to_pipe(:transaction_sample_data, transactions) if transactions
      end

      def error_data(errors)
        write_to_pipe(:error_data, errors) if errors
      end

      def error_event_data(events)
        write_to_pipe(:error_event_data, events) if events
      end

      def span_event_data(events)
        write_to_pipe(:span_event_data, events) if events
      end

      def sql_trace_data(sql)
        write_to_pipe(:sql_trace_data, sql) if sql
      end

      def shutdown(time)
        @pipe.close if @pipe
      end

      # Invokes the block it is passed.  This is used to implement HTTP
      # keep-alive in the NewRelicService, and is a required interface for any
      # Service class.
      def session
        yield
      end

      private

      def marshal_payload(data)
        dumped_data = Marshal.dump(data)

        if File.exist?(MARSHAL_CHECK_FILENAME)
          begin
            Marshal.load(dumped_data)
          rescue StandardError => e
            NewRelic::Agent.logger.error(
              "Failure unmarshalling message just dumped (PID: #{Process.pid}, size: #{dumped_data.size})\n" +
              "Data: #{data.inspect}\n" +
              "Backtrace:\n" + caller.join("\n").gsub(/^/, "\t"), e
            )
          end
        end

        return dumped_data
      end

      def write_to_pipe(endpoint, data)
        @pipe.write(marshal_payload([endpoint, data])) if @pipe
      end
    end
  end
end
