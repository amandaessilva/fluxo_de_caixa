class Preview < ApplicationRecord
  belongs_to :user
  validates :purpose, inclusion: { in: %w[xlsx backup] }
  scope :expired, -> { where('expires_at < ?', Time.current) }

  def payload=(value)
    self.encrypted_payload = encryptor.encrypt_and_sign(value.to_json)
  end
  def payload
    JSON.parse(encryptor.decrypt_and_verify(encrypted_payload))
  end
  def self.purge_expired! = expired.delete_all

  private
  def encryptor
    key = Rails.application.key_generator.generate_key('financial-preview-v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
