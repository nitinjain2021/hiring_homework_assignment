# frozen_string_literal: true

User = Struct.new(:first_name, :last_name, :email, :phone, :more_data) do
  def valid?
    first_name.length.positive? && last_name.length.positive? && (valid_email? || valid_phone?)
  end

  def valid_email?
    !(email =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i).nil?
  end

  def unique_key
    first_name + last_name
  end

  def santized_phone
    phone.gsub(/[^0-9]/, '')
  end

  def valid_phone?
    santized_phone.length == 10 && santized_phone =~ /^(\d{3})(\d{3})(\d{4})$/
  end

  def formatted_phone
    if santized_phone =~ /^(\d{3})(\d{3})(\d{4})$/
      "(#{Regexp.last_match(1)}) #{Regexp.last_match(2)}-#{Regexp.last_match(3)}"
    end
  end

  def formatted_json
    data = {
      firstName: first_name,
      lastName: last_name,
      moreData: more_data
    }
    data.merge!("email": email) if valid_email?
    data.merge!("phone": formatted_phone) if valid_phone?
    data
  end
end

class UserSanitizer
  require 'net/http'
  require 'json'

  def self.process
    @@result = []
    @@stored_keys = {}
    create_valid_records_hash
    store_output
  end

  def self.create_valid_records_hash
    records.each do |record|
      validate_and_store(record)
    end
  end

  def self.validate_and_store(record)
    user = User.new(record['firstName'], record['lastName'],
                    record['email'], record['moreData']['phone'],
                    more_data(record['moreData']))
    return unless user.valid?

    store_record
  end

  def self.store_record(user)
    if @@stored_keys.key?(user.unique_key)
      array_index = @@stored_keys[user.unique_key]
      @@result[array_index] = merge_data(user.formatted_json, @@result[array_index])
    else
      @@result << user.formatted_json
      @@stored_keys[user.unique_key] = @@result.size - 1
    end
  end

  def self.merge_data(new_data, existing_data)
    partial_hash = new_data.reject { |k, _v| k == :moreData }
    existing_data.merge!(partial_hash)
    existing_data[:moreData].merge!(new_data[:moreData])
    existing_data
  end

  def self.store_output
    data = @@result.sort_by { |user| [user[:lastName], user[:phone]] }

    File.open('transformed.json', 'w') do |f|
      f.write(JSON.pretty_generate(data))
    end
  end

  def self.load
    data = File.read 'transformed.json'
    puts JSON.parse(data)
  end

  def self.more_data(data)
    data.reject { |k, _v| k == 'phone' }
  end

  def self.records
    uri = URI('https://test-users-2020.herokuapp.com/api/users')

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new uri
      request['Authorization'] = 'Bearer abc123'
      response = http.request request
      JSON.parse(response.body)
    end
  end
end
