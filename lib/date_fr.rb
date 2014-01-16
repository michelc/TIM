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
