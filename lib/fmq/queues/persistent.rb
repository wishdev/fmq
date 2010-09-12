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
require File.dirname(__FILE__) + '/base'

module FreeMessageQueue
  # This is the base for the persistent queue concept
  #
  # Currently there are two implementations of this base
  #
  # 1. FilePersistentQueue
  # 2. SequelPersistentQueue
  class PersistentQueue < BaseQueue
    #Return a message
    def poll(request)
      message = locate_message
      return message.nil? ? nil : remove_message(read_message(message, true))
    end

    # add one message to the queue (will be persisted)
    def put(message)
      unless message.nil?
        begin
          prevalidate
          add_message(message) # check constraints and update stats

          persist_message(message)
        end
      end

      return !message.nil?
    end

    # remove all items from the queue
    def clear
      clear_messages
      @size = 0
      @bytes = 0
    end

    private

    def locate_message
      raise QueueException.new("[PersistentQueue] Must implement the locate_message function")
    end

    def read_message(filename, delete)
      raise QueueException.new("[PersistentQueue] Must implement the read_message function")
    end

    def persist_message(message)
      raise QueueException.new("[PersistentQueue] Must implement the persist_message function")
    end

    def clear_messages
      raise QueueException.new("[PersistentQueue] Must implement the clear_messages function")
    end

    def prevalidate
      raise QueueException.new("[PersistentQueue] Must implement the prevalidate function")
    end
  end
end
