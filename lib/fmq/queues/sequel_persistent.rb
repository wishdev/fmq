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
require File.dirname(__FILE__) + '/persistent'
require "sequel"
require 'json'

module FreeMessageQueue
  # This a FIFO queue that stores messages in the database via Sequel
  # It is one of teimplementations of the PersitentQueue class
  #
  #  queue_manager = FreeMessageQueue::QueueManager.new(true) do
  #    setup_queue "/mail_box/threez", FreeMessageQueue::SequelPersistentQueue do |q|
  #      q.connection_sting = "postgres://user:password@host:port/database_name"
  #      q.table_name = "messages"
  #      q.session_table_name = "messages"
  #      q.max_messages = 10000
  #    end
  #  end
  class SequelPersistentQueue < PersistentQueue
    attr_accessor :connection_string
    attr_reader :session_table_name, :table_name

    def bytes
      db_single_value(bytes_query, :bytes)
    end

    def peek(session_id, request)
      message_id = peek_message(session_id)
      [message_id.nil? ? nil : read_message(message_id, false), message_id]
    end

    def peek_grab(session_id, message_id, request)
      db_execute(delete_query(message_id)) == 1 ? 200 : 204
    end

    def size
      db_single_value(size_query, :size)
    end

    def table_name=(table_name)
      @table_name = table_name
    end

    def session_table_name=(table_name)
      @session_table_name = table_name
    end

  private

    def db_single_row(query)
      row = nil
      database do |db|
        row = db[query].first
      end
      row
    end

    def db_single_value(query, column)
      row = db_single_row(query)
      row[column] if row
    end

    def db_execute(query)
      database do |db|
        db.execute_dui query
      end
    end

    # Find a message for poll
    def locate_message
      db_single_value(locate_query, :message_id)
    end

    def peek_message(session_id)
      unless last_message_id = db_single_value(select_session_last_message_query(session_id), :last_message_id)
        db_execute(insert_session_query(session_id))
        last_message_id = 0
      end
      message_id = db_single_value(peek_query(last_message_id), :message_id)
      db_execute(update_session_query(message_id || last_message_id, session_id))
      message_id
    end

    # persist a message to the file system
    def persist_message(message)
      db_execute(insert_query(message))
    end

    def read_message(message_id, delete)
      message_data = db_single_row(select_query(message_id))
      message = FreeMessageQueue::Message.new(message_data[:payload], message_data[:content_type], message_data[:created_at])
      message.option = JSON.parse(message_data[:options])
      db_execute(delete_query(message_id)) if delete
      message
    end

    # remove all items from the queue
    def clear_messages
      db_execute(clear_query)
    end

    def prevalidate
    end

    def database(&block)
      Sequel.connect(@connection_string, &block)
    end

    def select_query(message_id)
      "SELECT payload, content_type, created_at, options FROM #{table_name} WHERE queue = '#{name}' AND valid = 1 AND message_id = #{message_id}"
    end

    def locate_query
      "SELECT message_id FROM #{table_name} WHERE queue = '#{name}' AND valid = 1 ORDER BY message_id LIMIT 1"
    end

    def bytes_query
      "SELECT coalesce(sum(bytes), 0) AS bytes FROM #{table_name} WHERE queue = '#{name}' AND valid = 1"
    end

    def size_query
      "SELECT count(*) AS size FROM #{table_name} WHERE queue = '#{name}' AND valid = 1"
    end

    def delete_query(message_id)
      "UPDATE #{table_name} SET valid = 0 WHERE message_id = #{message_id} AND valid = 1"
    end

    def clear_query
      "UPDATE #{table_name} SET valid = 0 WHERE queue = '#{name}'"
    end

    def insert_query(message)
      "INSERT INTO #{table_name} (queue, content_type, created_at, options, payload, bytes) VALUES ('#{name}', '#{message.content_type}', '#{message.created_at.to_s}', '#{message.option.to_json}', '#{message.payload}', #{message.payload.length})"
    end

    def peek_query(last_message_id)
      "SELECT message_id FROM #{table_name} WHERE queue = '#{name}' AND valid = 1 AND message_id > #{last_message_id} ORDER BY message_id LIMIT 1"
    end

    def select_session_last_message_query(session_id)
      "SELECT last_message_id FROM #{session_table_name} WHERE queue = '#{name}' AND session_id = '#{session_id}'"
    end

    def update_session_query(message_id, session_id)
      "UPDATE #{session_table_name} SET last_message_id = #{message_id}, last_used = now() WHERE queue = '#{name}' AND session_id = '#{session_id}'"
    end

    def insert_session_query(session_id)
      "INSERT INTO #{session_table_name} (queue, session_id, last_message_id) VALUES ('#{name}', '#{session_id}', 0)"
    end
  end
end