class Entry < ApplicationRecord
  include MonetaryPrecision
  KINDS = { 'income' => 'Entrada', 'expense' => 'Despesa', 'benefit_received' => 'Benefício recebido', 'benefit_used' => 'Benefício utilizado' }.freeze
  STATUSES = { 'planned' => 'Planejado', 'actual' => 'Realizado' }.freeze
  belongs_to :financial_year
  belongs_to :category
  belongs_to :recurring_rule, optional: true
  validates :date, :description, presence: true
  validates :description, length: { maximum: 250 }
  validates :amount, numericality: { greater_than: 0, less_than: 10**13 }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validate :date_matches_year
  scope :in_month, ->(year, month) { where(date: Date.new(year, month).all_month) }
  scope :outgoing, -> { where(kind: %w[expense benefit_used]) }

  private
  def date_matches_year
    errors.add(:date, 'deve pertencer ao ano financeiro') if date && financial_year && date.year != financial_year.year
  end
end
