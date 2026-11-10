class User < ApplicationRecord
  has_secure_password
  has_many :previews, dependent: :destroy
  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def google_calendar_connected?
    google_refresh_token_ciphertext.present? && google_calendar_id.present?
  end

  def google_refresh_token
    decrypt_google_token(google_refresh_token_ciphertext)
  end

  def google_refresh_token=(value)
    self.google_refresh_token_ciphertext = encrypt_google_token(value)
  end

  def google_access_token
    decrypt_google_token(google_access_token_ciphertext)
  end

  def google_access_token=(value)
    self.google_access_token_ciphertext = encrypt_google_token(value)
  end

  private

  def encrypt_google_token(value)
    return if value.blank?

    google_token_encryptor.encrypt_and_sign(value)
  end

  def decrypt_google_token(value)
    return if value.blank?

    google_token_encryptor.decrypt_and_verify(value)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def google_token_encryptor
    key = Rails.application.key_generator.generate_key('google-calendar-oauth-tokens', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
