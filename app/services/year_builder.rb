class YearBuilder
  def self.call(year, opening_balance: nil, copy_from: nil, populate: true)
    year = Integer(year)
    raise ArgumentError, 'Ano deve estar entre 1900 e 2200' unless (1900..2200).cover?(year)
    FinancialYear.transaction do
      existing = FinancialYear.find_by(year: year)
      return existing if existing
      previous = copy_from || FinancialYear.where('year < ?', year).order(year: :desc).first
      record = FinancialYear.create!(year: year, opening_balance: opening_balance || 0,
        previous_year: opening_balance.nil? ? previous : nil)
      previous&.monthly_limits&.find_each do |limit|
        record.monthly_limits.create!(category: limit.category, month: limit.month, amount: limit.amount)
      end
      RecurringRule.find_each { |rule| rule.materialize!(record) } if populate
      record
    end
  end
end
