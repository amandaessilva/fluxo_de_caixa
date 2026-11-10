require 'roo'
require 'zip'

class XlsxImporter
  class InvalidFile < StandardError; end
  MONTHS = %w[janeiro fevereiro marco abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  COLUMNS = { 7 => 'income', 8 => 'benefit_received', 9 => 'benefit_used', 10 => 'expense' }.freeze
  RANGES = { 'actual' => (6..126), 'planned' => (132..211) }.freeze
  MAX_BYTES = 10.megabytes

  def initialize(path, filename:, fallback_year:, force_year: false)
    @path, @filename, @fallback_year = path, filename, Integer(fallback_year)
    @warnings, @unparsed, @entries, @limits, @auxiliary = [], [], [], [], []
    @inferred = 0
    @force_year = force_year
    @adjusted_year_dates = 0
    @groups = []
    @formulas, @raw_numbers = {}, {}
  end

  def preview
    validate_archive!
    read_xml_metadata!
    book = Roo::Excelx.new(@path)
    sheets = book.sheets.filter_map { |name| month = month_for(name); [name, month] if month }
    raise InvalidFile, 'Nenhuma aba mensal reconhecida (Janeiro a Dezembro).' if sheets.empty?
    raise InvalidFile, 'Há mais de uma aba para o mesmo mês.' unless sheets.map(&:last).uniq.size == sheets.size
    @year = detect_year(book, sheets)
    sheets.each do |name, month|
      sheet = book.sheet(name)
      validate_headers!(sheet, name)
      RANGES.each { |status, rows| rows.each { |row| parse_row(sheet, name, month, status, row) } }
      parse_limits(sheet, name, month)
      inspect_outside_tables(sheet, name)
    end
    (book.sheets - sheets.map(&:first)).each { |name| inspect_auxiliary(book.sheet(name), name) }
    missing = (1..12).to_a - sheets.map(&:last)
    @warnings << "Meses sem aba: #{missing.join(', ')}." if missing.any?
    @warnings << 'As abas auxiliares listadas não serão convertidas automaticamente; revise parcelas e outros dados antes de confirmar.' if @auxiliary.any?
    data = { 'year' => @year, 'months' => sheets.map(&:last).sort, 'entries' => @entries,
      'groups' => (@groups + @entries.map { |e| e['category'] }).uniq, 'limits' => @limits, 'warnings' => @warnings.uniq, 'unparsed' => @unparsed,
      'adjusted_year_dates' => @adjusted_year_dates, 'forced_year' => @force_year, 'inferred_dates' => @inferred, 'auxiliary' => @auxiliary }
    data['summary'] = self.class.summary(@entries)
    data['fingerprint'] = self.class.fingerprint(@year)
    data
  rescue InvalidFile
    raise
  rescue StandardError => e
    raise InvalidFile, "Não foi possível ler o XLSX (#{e.class}). Verifique se o arquivo não está corrompido."
  ensure
    book&.close if book.respond_to?(:close)
  end

  def self.summary(entries)
    entries.group_by { |e| [e.fetch('date')[0, 7], e.fetch('status'), e.fetch('kind')].join('|') }.transform_values do |rows|
      { 'count' => rows.size, 'total' => rows.sum { |e| BigDecimal(e.fetch('amount')) }.to_s('F') }
    end
  end

  def self.fingerprint(year)
    record = FinancialYear.find_by(year: year)
    Digest::SHA256.hexdigest([record&.attributes, record&.entries&.order(:id)&.map(&:attributes),
      record&.monthly_limits&.order(:id)&.map(&:attributes)].to_json)
  end

  def self.commit!(data, replace: false)
    raise InvalidFile, 'Corrija os valores não interpretados e envie novamente.' if data.fetch('unparsed').any?
    FinancialYear.transaction do
      raise InvalidFile, 'Os dados mudaram desde a prévia. Envie novamente.' unless fingerprint(data.fetch('year')) == data.fetch('fingerprint')
      year = FinancialYear.find_by(year: data.fetch('year'))
      if year && (year.entries.exists? || year.monthly_limits.exists?) && !replace
        raise InvalidFile, 'Confirme explicitamente a substituição do ano existente.'
      end
      year ||= FinancialYear.create!(year: data.fetch('year'), opening_balance: 0)
      year.entries.destroy_all
      year.monthly_limits.destroy_all
      data.fetch('groups').each { |name| Category.find_or_create_by!(name: name) }
      data.fetch('limits').each do |attrs|
        category = Category.find_or_create_by!(name: attrs.fetch('category'))
        year.monthly_limits.create!(category: category, month: attrs.fetch('month'), amount: attrs.fetch('amount'))
      end
      data.fetch('entries').each do |attrs|
        category = Category.find_or_create_by!(name: attrs.fetch('category'))
        year.entries.create!(attrs.except('category', 'source').merge(category: category))
      end
      persisted = year.entries.map { |e| { 'date' => e.date.iso8601, 'status' => e.status, 'kind' => e.kind, 'amount' => e.amount.to_s('F') } }
      raise InvalidFile, 'A conferência dos totais falhou; nenhuma alteração foi salva.' unless summary(persisted) == data.fetch('summary')
      raise InvalidFile, 'A conferência de limites falhou.' unless year.monthly_limits.count == data.fetch('limits').size
      year
    end
  end

  private
  def normalize(value) = I18n.transliterate(value.to_s).downcase.strip
  def month_for(name)
    text = normalize(name).gsub(/[^a-z]/, '')
    index = MONTHS.index { |m| text == m || text == m[0, 3] }
    index && index + 1
  end

  def validate_archive!
    raise InvalidFile, 'Envie um arquivo com extensão .xlsx.' unless File.extname(@filename).downcase == '.xlsx'
    raise InvalidFile, 'Arquivo muito grande (máximo 10 MB).' if File.size(@path) > MAX_BYTES
    Zip::File.open(@path) do |zip|
      raise InvalidFile, 'Estrutura XLSX ausente.' unless zip.find_entry('xl/workbook.xml') && zip.find_entry('[Content_Types].xml')
      raise InvalidFile, 'Planilha descompactada excede 80 MB.' if zip.sum(&:size) > 80.megabytes
      raise InvalidFile, 'Planilha contém arquivos demais.' if zip.size > 3000
    end
  end

  # Roo lê células e datas. O XML complementa fórmulas sem cache (omitidas
  # pelo Roo) e preserva os dígitos monetários originais, sem passar por Float.
  def read_xml_metadata!
    Zip::File.open(@path) do |zip|
      workbook = Nokogiri::XML(zip.read('xl/workbook.xml'))
      relationships = Nokogiri::XML(zip.read('xl/_rels/workbook.xml.rels'))
      targets = relationships.xpath('//*[local-name()="Relationship"]').to_h { |r| [r['Id'], r['Target']] }
      workbook.xpath('//*[local-name()="sheet"]').each do |sheet|
        name = sheet['name']
        rid = sheet.attribute_nodes.find { |attr| attr.name == 'id' }&.value
        target = targets.fetch(rid)
        path = target.start_with?('/') ? target.delete_prefix('/') : Pathname.new("xl/#{target}").cleanpath.to_s
        xml = Nokogiri::XML(zip.read(path))
        @formulas[name], @raw_numbers[name] = {}, {}
        xml.xpath('//*[local-name()="c"]').each do |cell|
          match = cell['r'].to_s.match(/\A([A-Z]+)(\d+)\z/)
          next unless match
          col = match[1].chars.reduce(0) { |sum, char| sum * 26 + char.ord - 64 }
          row = match[2].to_i
          raise InvalidFile, "Aba #{name} excede 10.000 linhas ou 100 colunas." if row > 10_000 || col > 100
          key = [row, col]
          formula = cell.at_xpath('./*[local-name()="f"]')
          @formulas[name][key] = formula.text if formula
          value = cell.at_xpath('./*[local-name()="v"]')&.text
          @raw_numbers[name][key] = value if value.present? && (cell['t'].nil? || cell['t'] == 'n')
        end
      end
    end
  end

  def formula_present?(name, row, col) = @formulas.fetch(name, {}).key?([row, col])

  def detect_year(book, sheets)
    years = []
    sheets.each do |name, _|
      sheet = book.sheet(name)
      (1..4).each do |r|
        (1..14).each { |c| years.concat(sheet.cell(r,c).to_s.scan(/\b(?:19|20|21)\d{2}\b/).map(&:to_i)) }
      end
      RANGES.values.each { |rows| rows.each { |r| value = sheet.cell(r,1); years << value.year if value.is_a?(Date) || value.is_a?(Time) } }
    end
    # Em auxiliares, só interpretamos um ano rotulado, evitando confundir
    # uma quantia como 2026 com o calendário.
    (book.sheets - sheets.map(&:first)).each do |name|
      sheet = book.sheet(name)
      (1..[sheet.last_row.to_i, 10].min).each do |row|
        (1..14).each do |col|
          label = normalize(sheet.cell(row,col))
          next unless label.match?(/\bano\b/)
          years.concat(label.scan(/\b(?:19|20|21)\d{2}\b/).map(&:to_i))
          adjacent = sheet.cell(row,col+1).to_s
          years << adjacent.to_i if label.match?(/\Aano:?\z/) && adjacent.match?(/\A(?:19|20|21)\d{2}(?:\.0)?\z/)
        end
      end
    end
    years.uniq!
    raise InvalidFile, 'Ano de referência deve estar entre 1900 e 2200.' unless (1900..2200).cover?(@fallback_year)
    if @force_year
      @warnings << "Ano definido explicitamente: #{@fallback_year}. Anos encontrados nas células: #{years.join(', ').presence || 'nenhum'}. As datas serão ajustadas para o ano informado."
      return @fallback_year
    end
    raise InvalidFile, "Anos conflitantes na planilha: #{years.join(', ')}. Se estiver reaproveitando a planilha, selecione explicitamente o ano desejado." if years.size > 1
    if years.empty?
      @warnings << "Ano não identificado na planilha: será usado #{@fallback_year}, informado no formulário."
      @fallback_year
    else
      @warnings << "O ano identificado (#{years.first}) prevalece sobre o ano informado (#{@fallback_year})." if years.first != @fallback_year
      years.first
    end
  end

  def validate_headers!(sheet, name)
    raise InvalidFile, "Aba #{name} ultrapassa o limite de 10.000 linhas ou 100 colunas." if sheet.last_row.to_i > 10_000 || sheet.last_column.to_i > 100
    [1..5, 127..131].each_with_index do |range, index|
      # No modelo de referência H/I só são rotuladas em REALIZADO.
      # O bloco PREVISTO mantém essas mesmas colunas, sem repetir seus títulos.
      header_row = range.find { |r| normalize(sheet.cell(r,1)) == 'data' && normalize(sheet.cell(r,2)).match?(/descri/) }
      raise InvalidFile, "Cabeçalho de data/descrição ausente em #{name}, linhas #{range}." unless header_row
      headers = (1..10).to_h { |c| [c, normalize(sheet.cell(header_row,c))] }
      received = headers[8].match?(/benef|\Aent(?:rada)? vale\z/)
      used = headers[9].match?(/benef|\Asaid(?:a)? vale\z/)
      inherited = index == 1 && headers[8].blank? && headers[9].blank?
      valid = headers[7].match?(/entrada|receita/) && headers[10].match?(/saida|despesa/) && ((received && used) || inherited)
      raise InvalidFile, "Cabeçalhos financeiros não reconhecidos em #{name}, linha #{header_row}. Esperado G=entrada, H/I=benefícios ou vales, J=saída." unless valid
    end
  end

  def money(value)
    return nil if value.nil? || value.to_s.strip.empty?
    str = value.to_s.strip.delete('R$').gsub(/[[:space:]]/, '')
    str = str.delete('.').tr(',', '.') if str.include?(',')
    number = BigDecimal(str)
    raise ArgumentError unless number.finite? && number >= 0 && number < 10**13 && (number * 100).frac.zero?
    number
  end

  def parse_row(sheet, name, month, status, row)
    description = sheet.cell(row, 2).to_s.strip
    if normalize(description).match?(/\A(total|saldo|resumo)(\b|$)/)
      @warnings << "#{name}!#{row}: linha de resumo ignorada." if COLUMNS.keys.any? { |c| sheet.cell(row,c).present? }
      return
    end
    amounts = COLUMNS.filter_map do |col, kind|
      raw = @raw_numbers.dig(name, [row, col]) || sheet.cell(row, col)
      begin
        value = money(raw)
        if value.nil? && formula_present?(name, row, col)
          @unparsed << "#{name}!#{('A'.ord + col - 1).chr}#{row}: fórmula sem valor calculado."
        end
        [kind, value] if value && !value.zero?
      rescue ArgumentError
        @unparsed << "#{name}!#{('A'.ord + col - 1).chr}#{row}: #{raw.to_s.truncate(80)}"
        nil
      end
    end
    return if amounts.empty?
    date = parse_date(sheet.cell(row, 1), name, month, row)
    category = sheet.cell(row,4).to_s.strip.presence || 'Sem grupo'
    @warnings << "#{name}!#{row}: grupo ausente; usado Sem grupo." if category == 'Sem grupo'
    description = "Lançamento importado · #{name} linha #{row}" if description.empty?
    notes = sheet.cell(row,5).to_s
    interest = sheet.cell(row,6)
    if interest.present? && interest.to_s != '0'
      notes = [notes, "Juros mensais informados: #{interest}"].reject(&:blank?).join(' • ')
      @warnings << 'Juros da coluna F foram preservados nas observações; não geram lançamentos adicionais.'
    end
    amounts.each do |kind, amount|
      @entries << { 'date' => date.iso8601, 'description' => description, 'category' => category,
        'kind' => kind, 'status' => status, 'amount' => amount.to_s('F'),
        'payment_method' => sheet.cell(row,3).to_s.presence, 'notes' => notes.presence, 'source' => "#{name}!#{row}" }
    end
  end

  def parse_date(value, name, month, row)
    if value.blank?
      @inferred += 1
      return Date.new(@year, month, 15)
    end
    day = if value.is_a?(Date) || value.is_a?(Time)
      @adjusted_year_dates += 1 if value.year != @year
      @warnings << "#{name}!A#{row}: mês da data ajustado para o mês da aba." if value.month != month
      value.day
    elsif value.is_a?(Numeric)
      raise ArgumentError if value <= 31 && value != value.to_i
      value <= 31 ? value.to_i : (Date.new(1899,12,30) + value.to_i).day
    else
      str = value.to_s
      str.match?(/\A\d{1,2}\z/) ? str.to_i : Date.strptime(str, '%d/%m/%Y').day
    end
    Date.new(@year, month, day)
  rescue ArgumentError, Date::Error
    @unparsed << "#{name}!A#{row}: data inválida #{value.to_s.truncate(50)}."
    Date.new(@year, month, 15)
  end

  def parse_limits(sheet, name, month)
    (5..43).each do |row|
      category = sheet.cell(row,13).to_s.strip
      next if category.blank? || normalize(category).match?(/\A(grupo|categoria|total|limite|saldo)(s)?\z/)
      @groups << category
      raw = @raw_numbers.dig(name, [row, 14]) || sheet.cell(row,14)
      if raw.blank?
        @unparsed << "#{name}!N#{row}: fórmula de limite sem valor calculado." if formula_present?(name, row, 14)
        next
      end
      begin
        amount = money(raw)
        raise ArgumentError if @limits.any? { |l| l['month'] == month && l['category'] == category }
        @limits << { 'category' => category, 'month' => month, 'amount' => amount.to_s('F') }
      rescue ArgumentError
        @unparsed << "#{name}!N#{row}: limite inválido ou grupo duplicado (#{category})."
      end
    end
  end

  def inspect_outside_tables(sheet, name)
    balance_formulas = [6, 132].filter_map { |r| @formulas.dig(name, [r,11]).presence }
    if balance_formulas.any? { |f| f.match?(/G\d+/i) && f.match?(/J\d+/i) && !f.match?(/[HI]\d+/i) }
      @warnings << 'A coluna K contém fórmulas que consideram somente dinheiro. A aplicação recalcula os saldos incluindo benefícios recebidos e utilizados, conforme a regra do sistema.'
    end
    extra = []
    (1..sheet.last_row.to_i).each do |row|
      (22..sheet.last_column.to_i).each do |col|
        extra << "#{Roo::Utils.number_to_letter(col)}#{row}" if sheet.cell(row,col).present? || formula_present?(name,row,col)
      end
    end
    @warnings << "#{name}: #{extra.size} células fora das tabelas, não importadas: #{extra.join(', ')}. Revise esses valores antes de confirmar." if extra.any?
    (212..sheet.last_row.to_i).each do |row|
      # K é somente saldo calculado; sua presença não representa movimento extra.
      next unless (1..10).any? { |c| sheet.cell(row,c).present? || formula_present?(name,row,c) }
      @warnings << "#{name}: há dados após a linha 211 (primeira linha: #{row}); revise-os, pois não serão importados."
      break
    end
  end

  def inspect_auxiliary(sheet, name)
    raise InvalidFile, "Aba auxiliar #{name} excede 10.000 linhas ou 100 colunas." if sheet.last_row.to_i > 10_000 || sheet.last_column.to_i > 100
    rows, formulas, financial_rows = [], 0, []
    (1..sheet.last_row.to_i).each do |r|
      values = []
      (1..sheet.last_column.to_i).each do |c|
        if formula_present?(name, r, c)
          formulas += 1
        elsif sheet.cell(r,c).present?
          values << "#{('A'.ord+c-1).chr}: #{sheet.cell(r,c).to_s.truncate(100)}"
        end
      end
      item = { 'row' => r, 'values' => values.join(' | ') }
      rows << item if values.any?
      # Linhas avulsas no formato A:K após um resumo não são totais anuais.
      # Mostramos todas separadamente, mesmo quando ficam além da amostra inicial.
      if sheet.cell(r,2).is_a?(String) && sheet.cell(r,4).present? && COLUMNS.keys.any? { |c| v = sheet.cell(r,c); v.is_a?(Numeric) && v != 0 && !formula_present?(name,r,c) }
        financial_rows << item
      end
    end
    @warnings << "#{name}: #{financial_rows.size} possíveis lançamentos avulsos nas linhas #{financial_rows.map { |item| item['row'] }.join(', ')} não serão importados automaticamente. Revise datas e possíveis duplicatas; todos estão destacados na prévia." if financial_rows.any?
    formulas = @formulas.fetch(name, {}).size
    @auxiliary << { 'sheet' => name, 'non_formula_rows' => rows.size, 'formula_cells' => formulas, 'financial_rows' => financial_rows, 'sample' => rows.first(30) }
  end
end
