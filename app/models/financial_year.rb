class FinancialYear < ApplicationRecord
  include MonetaryPrecision
  belongs_to :previous_year, class_name: 'FinancialYear', optional: true
  has_many :entries, dependent: :destroy
  has_many :monthly_limits, dependent: :destroy
  validates :year, numericality: { only_integer: true, in: 1900..2200 }, uniqueness: true
  validates :opening_balance, numericality: true
  validate :previous_year_is_earlier

  # Um vínculo acompanha correções do fechamento anterior, sem misturar situações.
  def initial_balance(status)
    previous_year ? BalanceReport.new(previous_year, status: status).closing_balance : opening_balance
  end

  private
  def previous_year_is_earlier
    errors.add(:previous_year, 'deve ser anterior ao ano atual') if previous_year && previous_year.year >= year.to_i
  end
end
