# frozen_string_literal: true

User = Struct.new(:first_name, :last_name, :email, :phone, :more_data) do
  def valid?
    first_name.to_s.length.positive? && last_name.to_s.length.positive? && (valid_email? || valid_phone?)
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

  @@result = []
  @@stored_keys = {}

  def self.process
    create_valid_records_hash
    store_output
  rescue DownloadError => e
    puts e.inspect
  end

  def self.create_valid_records_hash
    Download.json.each do |record|
      validate_and_store(record)
    end
  end

  def self.validate_and_store(record)
    user = User.new(record['firstName'], record['lastName'],
                    record['email'], record['moreData']['phone'],
                    more_data(record['moreData']))
    return unless user.valid?

    store_record(user)
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
end

class Download
  URL = 'https://test-users-2020.herokuapp.com/api/users'
  TOKEN = 'Bearer abc123'

  def self.json
    uri = URI(URL)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new uri
      request['Authorization'] = TOKEN
      response = http.request request
      case response
      when Net::HTTPSuccess
        JSON.parse(response.body)
      when Net::HTTPUnauthorized
        raise DownloadError, JSON.parse(response.body)['error']
      else
        raise DownloadError
      end
    end
  end
end

class DownloadError < StandardError
  def initialize(msg = 'Something went wrong while fetching data from source')
    super
  end
end

# Few test cases for our user struct
describe User do
  context 'When testing the User Class validation' do
    it 'should not be valid with a malformed email and no phone' do
      user = User.new('Rob', 'Jason', 'invalid_email@none', '')
      expect(user.valid?).to eq false
    end

    it 'should not be valid with no email and invalid phone' do
      user = User.new('Rob', 'Jason', '', '123')
      expect(user.valid?).to eq false
    end

    it 'should be valid with valid email' do
      user = User.new('Rob', 'Jason', 'nj@gmail.com')
      expect(user.valid?).to eq true
    end
  end

  context 'When check formatting of object' do
    it 'should return hash with firstName lastName email moreData' do
      user = User.new('Rob', 'Jason', 'nj@gmail.com', '')
      expect(user.formatted_json.keys).to contain_exactly(:firstName, :lastName, :email, :moreData)
    end
  end
end
