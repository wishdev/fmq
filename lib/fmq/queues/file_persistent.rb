#
# Copyright (c) 2008 Vincent Landgraf
#
# Copyright (c) 2010 John W Higgin

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
require File.dirname(__FILE__) + '/persistent'
require "fileutils"

module FreeMessageQueue
  # This a FIFO queue that stores messages in the file system
  # It is one of the implementations of the PersitentQueue class
  #
  #  queue_manager = FreeMessageQueue::QueueManager.new(true) do
  #    setup_queue "/mail_box/threez", FreeMessageQueue::FilePersistentQueue do |q|
  #      q.folder = "./tmp/mail_box/threez"
  #      q.max_messages = 10000
  #    end
  #  end
  class FilePersistentQueue < PersistentQueue
    # *CONFIGURATION* *OPTION*
    # sets the path to the folder that holds all messages, this will
    # create the folder if it doesn't exist
    # also loads existing messages into the queue statistics
    def folder=(path)
      FileUtils.mkdir_p path unless File.exist? path
      @folder_path = path
      @size = 0
      @bytes = 0
      all_messages.each do |f|
        add_message(read_message(f, false))
      end
    end

  private

    # Find a message for poll
    def locate_message
      prevalidate
      return all_messages.sort!.first
    end

    # persist a message to the file system
    def persist_message(message)
      msg_bin = Marshal.dump(message)
      File.open(@folder_path + "/#{Time.now.to_f}.msg", "wb") do |f|
        f.write msg_bin
      end
    end

    def read_message(filename, delete)
      msg_bin = File.open(filename, "rb") { |f| f.read }
      FileUtils.rm filename if delete
      Marshal.load(msg_bin)
    end

    # remove all items from the queue
    def clear_messages
      FileUtils.rm all_messages
    end

    # returns an array with all paths to queue messages
    def all_messages
      Dir[@folder_path + "/*.msg"]
    end

    # raise an exceptin if the folder name is not set
    def prevalidate
      raise QueueException.new("[FilePersistentQueue] The folder_path need to be specified", caller) if @folder_path.nil?
    end
  end
end
