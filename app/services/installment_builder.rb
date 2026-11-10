class InstallmentBuilder
  # O valor recebido é o TOTAL da compra. Centavos restantes ficam nas primeiras parcelas.
  def self.call(attributes, count:)
    count = Integer(count)
    raise ArgumentError, 'Use entre 2 e 120 parcelas' unless (2..120).cover?(count)
    attrs = attributes.symbolize_keys
    raise ArgumentError, "Informe a descrição da compra" if attrs[:description].blank?
    date = Date.iso8601(attrs.fetch(:date).to_s)
    total = BigDecimal(attrs.fetch(:amount).to_s)
    raise ArgumentError, 'Informe um total positivo com até duas casas decimais' unless total.positive? && total * 100 == (total * 100).to_i
    cents = (total * 100).to_i
    raise ArgumentError, 'O total deve permitir parcelas de pelo menos R$ 0,01' if cents < count
    group = SecureRandom.uuid
    Entry.transaction do
      count.times.map do |index|
        due = date >> index
        year = YearBuilder.call(due.year)
        Entry.create!(attrs.except(:financial_year_id).merge(date: due, financial_year: year,
          amount: BigDecimal((cents / count + (index < cents % count ? 1 : 0)).to_s) / 100,
          status: 'planned', installment_group: group, installment_number: index + 1, installments_count: count,
          description: "#{attrs[:description]} (#{index + 1}/#{count})"))
      end
    end
  end
end
