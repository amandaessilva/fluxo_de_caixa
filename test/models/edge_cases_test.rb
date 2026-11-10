require 'test_helper'
class EdgeCasesTest < ActiveSupport::TestCase
  setup { setup_finances }
  teardown { @file&.close! }

  def rewrite_cell(address, value: nil, formula: nil)
    Zip::File.open(@file.path) do |zip|
      path = 'xl/worksheets/sheet1.xml'
      xml = Nokogiri::XML(zip.read(path))
      cell = xml.at_xpath("//*[local-name()='c'][@r='#{address}']")
      cell.children.remove
      cell.remove_attribute('t')
      cell.add_child("<f>#{formula}</f>") if formula
      cell.add_child("<v>#{value}</v>") unless value.nil?
      zip.get_output_stream(path) { |stream| stream.write(xml.to_xml) }
    end
  end

  test 'somas decimais não acumulam erros binários do SQLite' do
    10.times { entry(amount: '0.10', kind: 'income') }
    assert_equal BigDecimal('101.00'), BalanceReport.new(@year).closing_balance
    e = entry
    e.amount = '1.001'
    assert_not e.valid?
  end
  test 'fórmula financeira sem cache bloqueia e não desaparece silenciosamente' do
    @file = workbook
    rewrite_cell('G6', formula: 'SUM(G7:G8)')
    data = preview(@file)
    assert data['unparsed'].any? { |message| message.include?('G6') && message.include?('fórmula') }
    assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.commit!(data) }
  end
  test 'número monetário é lido dos dígitos originais do XML' do
    @file = workbook
    rewrite_cell('G6', value: '123456789012.34')
    data = preview(@file)
    assert_equal '123456789012.34', data['entries'].first['amount']
  end
  test 'data inválida é relatada em vez de ser inferida silenciosamente' do
    @file = workbook
    rewrite_cell('A6', value: 33)
    # 33 é serial Excel válido, mas resulta no dia 1, normalizado ao mês da aba.
    assert_equal '2026-01-01', preview(@file)['entries'].first['date']
    rewrite_cell('A6', value: 0)
    assert preview(@file)['unparsed'].any? { |message| message.include?('data inválida') }
  end
  test 'grupo sem limite também é preservado' do
    @file = workbook
    rewrite_cell('N6')
    data = preview(@file)
    assert_includes data['groups'], 'Teste sintético'
    assert_empty data['limits']
  end
  test 'cabeçalho incompatível rejeita arquivo' do
    @file = workbook
    rewrite_cell('G5')
    assert_raises(XlsxImporter::InvalidFile) { preview(@file) }
  end
  test 'erro em parcela posterior reverte o primeiro lançamento e o novo ano' do
    future = FinancialYear.create!(year: 2200)
    assert_no_difference(['FinancialYear.count', 'Entry.count']) do
      assert_raises(ArgumentError) do
        InstallmentBuilder.call({ date: '2200-12-15', description: 'Fora do intervalo', category_id: @category.id, kind: 'expense', amount: '10' }, count: 2)
      end
    end
    assert_equal 0, future.entries.count
  end
  test 'recorrência respeita vigência e ano futuro recebe regra junto das parcelas' do
    rule = RecurringRule.create!(category: @category, description: 'Fixa limitada', amount: 30, kind: 'expense', day: 31, starts_on: '2026-11-01', ends_on: '2027-02-28')
    rule.materialize!(@year)
    assert_equal 2, @year.entries.count
    InstallmentBuilder.call({ date: '2026-11-15', description: 'Compra', category_id: @category.id, kind: 'expense', amount: '100' }, count: 10)
    following = FinancialYear.find_by!(year: 2027)
    assert_equal 10, following.entries.count
    assert_equal 2, following.entries.where(recurring_rule: rule).count
  end
  test 'restauração com referência quebrada preserva base anterior' do
    existing = entry
    payload = BackupService.export
    payload['data']['entries'].first['category_id'] = 99999
    assert_raises(ActiveRecord::RecordInvalid) { BackupService.restore!(payload) }
    assert_equal existing.id, Entry.sole.id
  end
end
