require 'openssl'

module Pling
  module APN
    class Connection
      include Pling::Configurable

      def initialize(config)
        setup_configuration(config, :require => [:certificate])
        open
      end

      def open
        Pling.logger.info "#{self.class} -- Opening connection in #{Process.pid}"
        ssl_socket.connect

        self
      end

      def reopen
        close
        open
      end

      def open?
        not closed?
      end

      def close
        Pling.logger.info "#{self.class} -- Closing connection in #{Process.pid}"
        ssl_socket.close rescue true
        tcp_socket.close rescue true

        @ssl_socket = @tcp_socket = nil

        self
      end

      def closed?
        return true if ssl_socket.closed?
        tcp_socket.read_nonblock(1)
        return false
      rescue Errno::EAGAIN
        return false
      rescue Exception => e
        return !e.message.match(/read would block/)
      end

      def write(*args, &block)
        with_retries do
          raise IOError, "Connection closed" if closed?
          ssl_socket.write(*args, &block)
        end
      end
      
      def puts(*args, &block)
        with_retries do
          raise IOError, "Connection closed" if closed?
          ssl_socket.puts(*args, &block)
        end
      end

      def read(*args, &block)
        with_retries do
          raise IOError, "Connection closed" if closed?
          ssl_socket.read(*args, &block)
        end
      end
      
      def gets(*args, &block)
        with_retries do
          raise IOError, "Connection closed" if closed?
          ssl_socket.gets(*args, &block)
        end
      end

      protected

        def ssl_context
          @ssl_context ||= OpenSSL::SSL::SSLContext.new.tap do |context|
            certificate  = File.read(configuration[:certificate])

            context.cert = OpenSSL::X509::Certificate.new(certificate)
            context.key  = OpenSSL::PKey::RSA.new(certificate)
          end
        end

        def tcp_socket
          @tcp_socket ||= TCPSocket.new(configuration[:host], configuration[:port]).tap do |tcp_socket|
            tcp_socket.setsockopt(Socket::SOL_SOCKET,  Socket::SO_KEEPALIVE, true)
            tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY,  true)
          end
        end

        def ssl_socket
          @ssl_socket ||= OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context) do |ssl_socket|
            ssl_socket.sync = true
          end
        end

      private

        def default_configuration
          super.merge(
            :host => 'gateway.push.apple.com',
            :port => 2195
          )
        end

        def with_retries(count = 3)
          yield
        rescue OpenSSL::SSL::SSLError, SocketError, SystemCallError, IOError
          if (count -= 1) > 0
            Pling.logger.info "#{self.class} -- #{$!.message}"
            reopen; retry
          else
            raise IOError, $!.message
          end
        end
    end
  end
end
