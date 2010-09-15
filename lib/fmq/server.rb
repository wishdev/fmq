#!/usr/bin/env ruby -wKU
#
# Copyright (c) 2008 Vincent Landgraf
#
# Copyright (c) 2010 John W Higgins
#
# This file is part of the Free Message Queue.
#
# Free Message Queue is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Free Message Queue is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Free Message Queue.  If not, see <http://www.gnu.org/licenses/>.
#

require 'yaml'
require 'securerandom'

module FreeMessageQueue
  # This implements server that plugs the free message queue into a rack enviroment
  class Server
    # When creating a server you have to pass the QueueManager
    def initialize(queue_manager)
      @queue_manager = queue_manager
      @log = FreeMessageQueue.logger
    end

    # Process incoming request and send them to the right sub processing method like <em>process_get</em>
    def call(env)
      request = Rack::Request.new(env)
      method = env['REQUEST_METHOD'].upcase
      if method == "POST"
        method = request['_method'] || 'POST'
        method = method.to_s.upcase
      end

      queue_path = request.env["PATH_INFO"]
      @log.debug("[Server] Request params: #{YAML.dump(request.params)})")

      response = nil
      begin
        # process supported features
        if method.match(/^(GET|POST|HEAD|DELETE|CLEAR|PEEK|PEEK_GRAB)$/) then
          response = self.send("process_" + method.downcase, request, queue_path)
        else
          response = client_exception(request, queue_path,
            ArgumentError.new("[Server] Method is not supported '#{method}'"))
        end
      rescue QueueException => ex
        response = client_exception(request, queue_path, ex)
      rescue QueueManagerException => ex
        response = client_exception(request, queue_path, ex)
      end

      response.header["SERVER"] = SERVER_HEADER
      return response.finish
    end

  protected

    # Returns an item from queue and sends it to the client.
    # If there is no item to fetch send an 204 (NoContent) and same as HEAD
    def process_get(request, queue_path)
      message = @queue_manager.poll(queue_path, request)
      prep_message_response('GET', message, queue_path)
    end

    # Put new item to the queue and and return sam e as head action (HTTP 200)
    def process_post(request, queue_path)
      @log.debug("[Server] Response to POST (200)")
      post_body = request.body.read
      message = Message.new(post_body, request.content_type)
      @log.debug("[Server] Message payload: #{post_body}")

      # send all options of the message back to the client
      for option_name in request.env.keys
        if option_name.match(/HTTP_MESSAGE_([a-zA-Z][a-zA-Z0-9_\-]*)/)
          message.option[$1] = request.env[option_name]
        end
      end

      @queue_manager.put(queue_path, message)

      response = Rack::Response.new([], 200)
      response.header["QUEUE_SIZE"] = @queue_manager.queue(queue_path).size.to_s
      response.header["QUEUE_BYTES"] = @queue_manager.queue(queue_path).bytes.to_s
      response
    end

    # Just return server header and queue size (HTTP 200)
    def process_head(request, queue_path)
      @log.debug("[Server] Response to HEAD (200)")

      response = Rack::Response.new([], 200)
      response.header["QUEUE_SIZE"] = @queue_manager.queue(queue_path).size.to_s
      response.header["QUEUE_BYTES"] = @queue_manager.queue(queue_path).bytes.to_s
      response
    end

    # Delete the queue and return server header (HTTP 200)
    def process_delete(request, queue_path)
      @log.debug("[Server] Response to DELETE (200)")
      @queue_manager.delete_queue(queue_path)

      response = Rack::Response.new([], 200)
    end

    # Clear the queue and return server header (HTTP 200)
    def process_clear(request, queue_path)
      @log.debug("[Server] Response to CLEAR (200)")
      @queue_manager.clear_queue(queue_path)

      response = Rack::Response.new([], 200)
    end

    def process_peek(request, queue_path)
      session_id = request.env['HTTP_FMQ_QUEUE_SESSION'] || SecureRandom.hex(10)
      message, message_id = @queue_manager.peek(queue_path, session_id, request)
      response = prep_message_response('PEEK', message, queue_path)
      if response.status == 200
        response['FMQ_QUEUE_SESSION'] = session_id.to_s
        response['FMQ_MESSAGE'] = message_id.to_s
      end
      response
    end

    def process_peek_grab(request, queue_path)
      session_id = request.env['HTTP_FMQ_QUEUE_SESSION']
      message_id = request.env['HTTP_FMQ_GRAB_MESSAGE']
      status = @queue_manager.peek_grab(queue_path, session_id, message_id, request)

      @log.debug("[Server] Response to PEEK_GRAB (#{status})")
      response = Rack::Response.new([], status)
    end

    def prep_message_response(method, message, queue_path)
      unless message.nil?
        if message.class == Rack::Response
          response = message
          @log.debug("[Server] Response to #{method} (#{response.status})")
        else
          response = Rack::Response.new([], 200)

          @log.debug("[Server] Response to #{method} (200)")
          response.header["CONTENT-TYPE"] = message.content_type
          response.header["QUEUE_SIZE"] = @queue_manager.queue(queue_path).size.to_s
          response.header["QUEUE_BYTES"] = @queue_manager.queue(queue_path).bytes.to_s

          # send all options of the message back to the client
          if message.respond_to?(:option) && message.option.size > 0
            for option_name in message.option.keys
              response.header["MESSAGE_#{option_name.gsub("-", "_").upcase}"] = message.option[option_name].to_s
            end
          end

          if !message.payload.nil? && message.bytes > 0
            @log.debug("[Server] Message payload: #{message.payload}")
            response.write(message.payload)
          end
        end
      else
        response = Rack::Response.new([], 204)
        @log.debug("[Server] Response to #{method} (204)")
        response.header["QUEUE_SIZE"] = response["QUEUE_BYTES"] = 0.to_s
      end
      response
    end

    # Inform the client that he did something wrong (HTTP 400).
    # HTTP-Header field Error contains information about the problem.
    # The client errorwill also be reported to warn level of logger.
    def client_exception(request, queue_path, ex)
      @log.warn("[Server] Client error: #{ex}")

      response = Rack::Response.new([], 400)
      response.header["ERROR"] = ex.message
      return response
    end
  end
end
