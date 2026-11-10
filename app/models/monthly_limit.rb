class MonthlyLimit < ApplicationRecord
  include MonetaryPrecision
  belongs_to :financial_year
  belongs_to :category
  validates :month, inclusion: { in: 1..12 }, uniqueness: { scope: [:financial_year_id, :category_id] }
  validates :amount, numericality: { greater_than_or_equal_to: 0, less_than: 10**13 }
end
