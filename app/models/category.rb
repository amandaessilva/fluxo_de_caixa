class Category < ApplicationRecord
  has_many :entries, dependent: :restrict_with_error
  has_many :recurring_rules, dependent: :restrict_with_error
  has_many :monthly_limits, dependent: :destroy
  normalizes :name, with: ->(name) { name.strip }
  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
end
