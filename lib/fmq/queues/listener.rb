#
# Copyright (c) 2008 John W Higgins
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
require 'socket'
require 'thread'
require File.dirname(__FILE__) + '/file_persistent'
require File.dirname(__FILE__) + '/sequel_persistent'
require 'ap'

module FreeMessageQueue
  # The ListenerQueue implements a little wrapper around the
  # FilePersistentQueue to make it thread safe and allow
  # for clients to leave callback sockets to get notified when
  # messages arrive.
  #
  #  queue_manager = FreeMessageQueue::ListenerQueue.new(true) do
  #    setup_queue "/fmq_test/test1" do |q|
  #      q.max_messages = 1000000
  #      q.max_size = 10.kb
  #    end
  #  end
  module ListenerQueue

    def initialize(manager)
      super(manager)
      @semaphore = Mutex.new
      @listeners = Array.new
    end

    # Returns one item from the queue
    def poll(request)
      @semaphore.synchronize {
        retval = super
        unless retval || (request && request.env['HTTP_LISTENER_PORT'].nil?)
          @listeners << "#{request.ip}:#{request.env['HTTP_LISTENER_PORT']}"
          @listeners.uniq!
          retval = Rack::Response.new([], 202)
        end
        retval
      }
    end

    # Puts one message to the queue
    def put(message)
      @semaphore.synchronize {
        super
        until @listeners.empty?
          begin
            listener = @listeners.pop
            sock = TCPSocket.open(*listener.split(':'))
            sock.close
          rescue
            nil
          end
        end
      }
    end

    # Returns one item from the queue
    def peek(session_id, request)
      @semaphore.synchronize {
        retval = super
        unless retval[0] || (request && request.env['HTTP_LISTENER_PORT'].nil?)
          @listeners << "#{request.ip}:#{request.env['HTTP_LISTENER_PORT']}"
          @listeners.uniq!
          retval = Rack::Response.new([], 202)
          retval.header['FMQ_QUEUE_SESSION'] = session_id.to_s
        end
        retval
      }
    end

  end

  class FileListenerQueue < FilePersistentQueue
    include ListenerQueue
  end

  class SequelListenerQueue < SequelPersistentQueue
    include ListenerQueue
  end
end
