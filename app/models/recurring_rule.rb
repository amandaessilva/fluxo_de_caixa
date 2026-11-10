class RecurringRule < ApplicationRecord
  include MonetaryPrecision
  belongs_to :category
  has_many :entries, dependent: :nullify
  validates :description, :starts_on, presence: true
  validates :amount, numericality: { greater_than: 0, less_than: 10**13 }
  validates :day, inclusion: { in: 1..31 }
  validates :kind, inclusion: { in: Entry::KINDS.keys }
  validate { errors.add(:ends_on, 'deve ser posterior ao início') if ends_on && starts_on && ends_on < starts_on }

  # Chave única evita duplicação ao materializar o mesmo ano novamente.
  def materialize!(financial_year)
    (1..12).each do |month|
      date = Date.new(financial_year.year, month, [day, Date.new(financial_year.year, month, -1).day].min)
      next if date < starts_on || (ends_on && date > ends_on)
      Entry.find_or_create_by!(source_key: "fixed:#{id}:#{date.strftime('%Y-%m')}") do |entry|
        entry.assign_attributes(financial_year: financial_year, category: category, recurring_rule: self,
          date: date, description: description, kind: kind, status: 'planned', amount: amount, payment_method: payment_method)
      end
    end
  end
end
