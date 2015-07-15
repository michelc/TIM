# encoding: UTF-8

# DateFR version 1.0.0
#
# Version francisée des constantes qui stockent les noms de mois et de jours
# en anglais dans lib/ruby/.../date.rb.
#

class Date

  # Nom complet des mois, en Français.
  MONTHNAMES = [nil] + %w(Janvier Février Mars Avril Mai Juin Juillet
                          Août Septembre Octobre Novembre Décembre)

  # Nom complet des jours, en Français.
  DAYNAMES = %w(Dimanche Lundi Mardi Mercredi Jeudi Vendredi Samedi)

  # Nom abrégé des mois, en Français.
  ABBR_MONTHNAMES = [nil] + %w(Jan Fév Mar Avr Mai Jun
                               Jui Aoû Sep Oct Nov Déc)

  # Nom abrégé des jours, en Français.
  ABBR_DAYNAMES = %w(Dim Lun Mar Mer Jeu Ven Sam)

  [MONTHNAMES, DAYNAMES, ABBR_MONTHNAMES, ABBR_DAYNAMES].each do |xs|
    xs.each{|x| x.freeze unless x.nil?}.freeze
  end

  def is_today?
    self == Date.today
  end

  def is_ferie?
    # Jours fériés fixes
    feries = [
               [ 1, 1 ],
               [ 5, 1 ],
               [ 5, 8 ],
               [ 7, 14 ],
               [ 8, 15 ],
               [ 11, 1 ],
               [ 11, 11 ],
               [ 12, 25 ]
             ]
    # Calcul dimanche de Pâques
    y = self.year
    a = y % 19
    b = y / 100
    c = y % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month = (h + l - 7 * m + 114) / 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    paques = Date.new(y, month, day)
    # Jours fériés liés à Pâques
    lundi_paques = paques.next
    feries << [ lundi_paques.month, lundi_paques.day ]
    ascension = paques.next_day(39)
    feries << [ ascension.month, ascension.day ]
    pentecote = paques.next_day(50)
    feries << [ pentecote.month, pentecote.day ]

    feries.include? [ self.month, self.day ]
  end

end

class DateTime

  alias :strftime_nolocale :strftime

  def strftime(format)
    format = format.dup
    format.gsub!(/%a/, Date::ABBR_DAYNAMES[self.wday])
    format.gsub!(/%A/, Date::DAYNAMES[self.wday])
    format.gsub!(/%b/, Date::ABBR_MONTHNAMES[self.mon])
    format.gsub!(/%B/, Date::MONTHNAMES[self.mon])

    self.strftime_nolocale(format)
  end

end
