# --- HELPERS (KERNEL) ---
module Kernel
  def safe_check_bitmap_file(params)
    begin
      res = pbCheckPokemonBitmapFiles(params)
      return false if !res
      return true if params[4].to_i == 0
      # El motor de RPG Maker devuelve la forma base si no encuentra la alternativa (fallback silencioso).
      # Si estamos buscando una forma específica, el nombre del archivo en disco TIENE QUE contener _X.
      return res.include?("_#{params[4]}.") || res.include?("_#{params[4]}b") || res.include?("_#{params[4]}s") || res.include?("_#{params[4]}f") || res.match(/_#{params[4]}$/) != nil || res.include?("_#{params[4]}_")
    rescue
      return false
    end
  end

  def pbFormLegend_FINAL(pkmn)
    return "" if !pkmn
    species_name = PBSpecies.getName(pkmn.species) rescue ""
    ids = []
    names = {}
    ids << 0
    names[0] = "Normal"

    begin
      if safe_check_bitmap_file([pkmn.species, 0, false, false, 1])
        ids << 1
        names[1] = "Mega (con estadísticas)"
        ids << 2
        names[2] = "Mega (solo sprite)"
      end
    rescue
    end

    begin
      # No se usan entradas Mega Y en el esquema numérico final.
    rescue
    end

    begin
      if safe_check_bitmap_file([pkmn.species, 0, false, false, 3])
        ids << 3
        names[3] = "Mega X (con estadísticas)"
        ids << 4
        names[4] = "Mega X (solo sprite)"
      end
    rescue
    end

    begin
      if safe_check_bitmap_file([pkmn.species, 0, false, false, 20])
        ids << 20
        names[20] = "Regional (Alola)"
      end
    rescue
    end

    begin
      if safe_check_bitmap_file([pkmn.species, 0, false, false, 30])
        ids << 30
        names[30] = "Regional (Galar)"
      end
    rescue
    end

    begin
      if safe_check_bitmap_file([pkmn.species, 0, false, false, 40])
        ids << 40
        names[40] = "Regional (Hisui)"
      end
    rescue
    end

    begin
      (20..29).each do |i|
        next if ids.include?(i)
        next if !safe_check_bitmap_file([pkmn.species, 0, false, false, i])
        ids << i
        n = pbGetMessage(MessageTypes::FormNames, pkmn.species).split(",")[i] rescue nil
        names[i] = (n && n.strip != "") ? ("Alola: " + n.strip) : ("Alola Forma " + (i - 19).to_s)
      end
    rescue
    end

    begin
      (30..39).each do |i|
        next if ids.include?(i)
        next if !safe_check_bitmap_file([pkmn.species, 0, false, false, i])
        ids << i
        n = pbGetMessage(MessageTypes::FormNames, pkmn.species).split(",")[i] rescue nil
        names[i] = (n && n.strip != "") ? ("Galar: " + n.strip) : ("Galar Forma " + (i - 29).to_s)
      end
    rescue
    end

    begin
      (40..49).each do |i|
        next if ids.include?(i)
        next if !safe_check_bitmap_file([pkmn.species, 0, false, false, i])
        ids << i
        n = pbGetMessage(MessageTypes::FormNames, pkmn.species).split(",")[i] rescue nil
        names[i] = (n && n.strip != "") ? ("Hisui: " + n.strip) : ("Hisui Forma " + (i - 39).to_s)
      end
    rescue
    end

    begin
      for i in 2..25
        next if ids.include?(i)
        if safe_check_bitmap_file([pkmn.species, 0, false, false, i])
          ids << i
          n = pbGetMessage(MessageTypes::FormNames, pkmn.species).split(",")[i] rescue nil
          names[i] = (n && n.strip != "") ? n.strip : ("Forma " + i.to_s)
        end
      end
    rescue
    end

    ids = ids.uniq.sort
    lines = []
    lines << ("Formas detectadas para " + species_name.to_s + ":")
    ids.each do |id|
      label = names[id] || ""
      lines << sprintf("%03d - %s", id, label)
    end
    lines << ""
    lines << "Tip: 002/004 = Mega solo sprite (sin estadísticas)." if ids.any? { |v| v == 2 || v == 4 }
    return lines.join("\n")
  end

  def pbGetNaturalMoves_FINAL(pkmn)
    return [] rescue [] if !pkmn
    ret = []
    
    # 1. Movimientos por nivel (naturales)
    begin
      mlist = pkmn.getMoveList; for m in mlist; ret.push(m[1]); end
    rescue; end
    
    # 2. Movimientos de MT/MO
    begin
      for i in 1...PBMoves.maxValue
        begin
          item_name = PBMoves.getName(i)
          if item_name && pkmn.isCompatibleWithMove?(i)
            ret.push(i)
          end
        rescue; end
      end
    rescue; end
    
    # 3. Movimientos de huevo
    begin
      esp = pkmn.species
      begin; esp = pbGetBabySpecies(esp); rescue; end
      pbRgssOpen("Data/eggEmerald.dat", "rb") { |f|
        f.pos = (esp - 1) * 8
        offset = f.fgetdw; length = f.fgetdw
        if length > 0; f.pos = offset; length.times { ret.push(f.fgetw) }; end
      }
    rescue; end
    
    return ret.uniq
  end

  def pbGetMoveHelp_FINAL(m_id)
    return "" if m_id <= 0
    begin
      d = PBMoveData.new(m_id)
      t = PBTypes.getName(d.type).upcase
      c = (["FIS", "ESP", "EST"][d.category]) || "???"
      p = d.basedamage > 0 ? d.basedamage.to_s : "---"
      a = d.accuracy > 0 ? d.accuracy.to_s : "---"
      de = pbGetMessage(MessageTypes::MoveDescriptions, m_id).to_s
      return "[" + t + "] " + c + " | P:" + p + " A:" + a + "\n" + de
    rescue; return ""; end
  end

  def pbGetItemHelp_FINAL(item_id)
    return "" if item_id <= 0
    begin
      name = PBItems.getName(item_id)
      desc = pbGetMessage(MessageTypes::ItemDescriptions, item_id).to_s
      # Intentar obtener tipo del objeto si está disponible
      item_type = ""
      begin
        if defined?(PBItemData) && PBItemData.respond_to?(:new)
          item_data = PBItemData.new(item_id)
          if item_data.respond_to?(:type)
            item_type = PBTypes.getName(item_data.type) rescue ""
          end
        end
      rescue; end
      
      # Buscar referencias a tipos en la descripción
      type_hints = []
      all_types = []
      begin
        for i in 0..PBTypes.maxValue
          begin
            tname = PBTypes.getName(i)
            all_types.push([i, tname.downcase]) if tname && tname != ""
          rescue; end
        end
      rescue; end
      
      desc_lower = desc.downcase
      all_types.each do |type_id, type_name|
        if desc_lower.include?(type_name) || name.downcase.include?(type_name)
          type_hints.push(PBTypes.getName(type_id).upcase) rescue nil
        end
      end
      
      type_str = type_hints.uniq.first || item_type || ""
      type_prefix = type_str != "" ? "[" + type_str + "] " : ""
      
      return type_prefix + desc
    rescue; return ""; end
  end

  def pbChooseItemAdvanced_FINAL(pkmn, msgwindow=nil)
    return 0 if !pkmn
    
    # Crear lista de todos los objetos
    all_items = []
    begin
      max_items = PBItems.maxValue rescue 500
      for i in 1...max_items
        begin
          name = PBItems.getName(i)
          if name && name != ""
            all_items.push([i, name])
          end
        rescue
          next
        end
      end
    rescue
      # Fallback si hay error
    end
    
    all_items.sort! { |a, b| a[1] <=> b[1] }
    filter = ""
    
    loop do
      begin
        msgwindow.visible = true if msgwindow
        cmds = []; ids = []; help = []
        
        label = filter == "" ? "[BUSCADOR: ...]" : ("[FILTRO: " + filter + "]")
        cmds.push(label); ids.push(-1); help.push("Escribe para filtrar por nombre o descripción. Busca por tipo (ej: dragón).")
        cmds.push("[QUITAR OBJETO]"); ids.push(-2); help.push("Quita el objeto equipado del Pokémon.")
        
        for it in all_items
          desc = pbGetItemHelp_FINAL(it[0])
          # Buscar por nombre, descripción o tipo
          match = false
          if filter == ""
            match = true
          else
            filter_lower = filter.downcase
            match = it[1].downcase.include?(filter_lower) || desc.downcase.include?(filter_lower)
          end
          
          if match
            pre = (pkmn.item == it[0]) ? "* " : "  "
            cmds.push(pre + it[1]); ids.push(it[0]); help.push(desc)
          end
        end
        
        idx = Kernel.pbShowCommandsWithHelp(msgwindow, cmds, help, -1)
        return 0 if idx < 0
        sel_id = ids[idx]
        if sel_id == -1
          filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
        elsif sel_id == -2
          # Quitar objeto
          pkmn.setItem(0) if pkmn.respond_to?(:setItem)
          return 0
        else
          # Equipar objeto seleccionado
          pkmn.setItem(sel_id) if pkmn.respond_to?(:setItem)
          return sel_id
        end
      rescue
        return 0
      end
    end
  end

  def pbChooseAbilitySelection_FINAL(pkmn, msgwindow=nil)
    natural_abs = []
    begin; alist = pkmn.getAbilityList; for a in alist; natural_abs.push(a[0]); end; rescue; end
    all_abs = []
    for i in 1...PBAbilities.maxValue
      begin; name = PBAbilities.getName(i); all_abs.push([i, name]) if name && name != ""; rescue; end
    end
    all_abs.sort! { |a, b| a[1] <=> b[1] }
    filter = ""
    loop do
      msgwindow.visible = true if msgwindow
      cmds = []; ids = []; help = []
      if filter == "*"
        label = "[FILTRO: * (solo naturales)]"
        cmds.push(label); ids.push(-1); help.push("Mostrando solo las habilidades naturales.")
        cmds.push("[RESETEAR]"); ids.push(-2); help.push("Vuelve a la habilidad natural.")
        for ab in all_abs
          if natural_abs.include?(ab[0])
            cmds.push("* " + ab[1]); ids.push(ab[0])
            desc = ""; begin; desc = pbGetMessage(MessageTypes::AbilityDescs, ab[0]).to_s; rescue; end
            help.push(desc)
          end
        end
      else
        label = filter == "" ? "[BUSCADOR: ...]" : ("[FILTRO: " + filter + "]")
        cmds.push(label); ids.push(-1); help.push("Escribe para filtrar por nombre o descripción. Escribe * para ver naturales.")
        cmds.push("[RESETEAR]"); ids.push(-2); help.push("Vuelve a la habilidad natural.")
        for ab in all_abs
          desc = ""; begin; desc = pbGetMessage(MessageTypes::AbilityDescs, ab[0]).to_s; rescue; end
          if filter == "" || ab[1].downcase.include?(filter.downcase) || desc.downcase.include?(filter.downcase)
            pre = natural_abs.include?(ab[0]) ? "* " : "  "
            cmds.push(pre + ab[1]); ids.push(ab[0])
            help.push(desc)
          end
        end
      end
      idx = Kernel.pbShowCommandsWithHelp(msgwindow, cmds, help, -1)
      return nil if idx < 0
      sel_id = ids[idx]
      if sel_id == -1
        filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
      elsif sel_id == -2
        return 0
      else
        return sel_id
      end
    end
  end

  def pbChooseNatureSelection_FINAL(pkmn, msgwindow=nil)
    all_natures = []
    stats = ["Ataque", "Defensa", "Velocidad", "At.Esp.", "Def.Esp."]
    count = (PBNatures.respond_to?(:getCount) ? PBNatures.getCount : 25) rescue 25
    for i in 0...count
      begin
        name = PBNatures.getName(i)
        next if !name || name == ""
        inc_stat = i / 5
        dec_stat = i % 5
        if inc_stat == dec_stat
          desc = "Naturaleza Neutra (Sin cambios en estadísticas)."
        else
          desc = "+10% " + stats[inc_stat] + "  |  -10% " + stats[dec_stat]
        end
        all_natures.push([i, name, desc])
      rescue
      end
    end
    all_natures.sort! { |a, b| a[1] <=> b[1] }
    
    filter = ""
    loop do
      msgwindow.visible = true if msgwindow
      cmds = []; ids = []; help = []
      
      label = filter == "" ? "[BUSCADOR: ...]" : ("[FILTRO: " + filter + "]")
      cmds.push(label); ids.push(-1); help.push("Escribe para filtrar por nombre o descripción.")
      cmds.push("[RESETEAR]"); ids.push(-99); help.push("Vuelve a la naturaleza generada naturalmente.")
      
      for nat in all_natures
        if filter == "" || nat[1].downcase.include?(filter.downcase) || nat[2].downcase.include?(filter.downcase)
          pre = (pkmn && pkmn.nature == nat[0]) ? "* " : "  "
          cmds.push(pre + nat[1])
          ids.push(nat[0])
          help.push(nat[2])
        end
      end
      
      idx = Kernel.pbShowCommandsWithHelp(msgwindow, cmds, help, -1)
      return nil if idx < 0
      sel_id = ids[idx]
      
      if sel_id == -1
        filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
      else
        return sel_id
      end
    end
  end

  def pbChooseMoveAdvanced_FINAL(pkmn, msgwindow=nil)
    return 0 if !pkmn
    
    # Movimientos por nivel (siempre funciona)
    natural_moves = []
    begin
      mlist = pkmn.getMoveList
      for m in mlist
        natural_moves.push(m[1]) if m && m[1] && m[1] > 0
      end
    rescue
      # Si falla, usar array vacío
    end
    
    # Movimientos de huevo (intento seguro)
    begin
      esp = pkmn.species
      if esp && esp > 0
        begin; esp = pbGetBabySpecies(esp); rescue; end
        if FileTest.exist?("Data/eggEmerald.dat")
          pbRgssOpen("Data/eggEmerald.dat", "rb") { |f|
            if f
              f.pos = (esp - 1) * 8
              offset = f.fgetdw; length = f.fgetdw
              if length > 0 && length < 1000  # Validación extra
                f.pos = offset; 
                length.times { 
                  move_id = f.fgetw rescue nil
                  natural_moves.push(move_id) if move_id && move_id > 0 && move_id < 1000
                } 
              end
            end
          }
        end
      end
    rescue
      # Ignorar errores de huevo
    end
    
    # MT/MO (intento muy seguro)
    begin
      # Solo intentar si la función existe
      if pkmn.respond_to?(:isCompatibleWithMove?)
        # Limitar a primeros 500 movimientos para evitar bucles largos
        for i in 1...[500, PBMoves.maxValue].min
          begin
            move_name = PBMoves.getName(i)
            if move_name && move_name != ""
              # Verificar compatibilidad con timeout implícito
              begin
                Timeout::timeout(0.001) do
                  if pkmn.isCompatibleWithMove?(i)
                    natural_moves.push(i) unless natural_moves.include?(i)
                  end
                end
              rescue
                # Si timeout o error, ignorar este movimiento
                next
              end
            end
          rescue
            next
          end
        end
      end
    rescue
      # Ignorar errores de MT/MO
    end
    
    # Crear lista de todos los movimientos
    all_moves = []
    for i in 1...PBMoves.maxValue
      begin
        name = PBMoves.getName(i)
        if name && name != ""
          all_moves.push([i, name])
        end
      rescue
        next
      end
    end
    
    all_moves.sort! { |a, b| a[1] <=> b[1] }
    filter = ""
    
    loop do
      begin
        msgwindow.visible = true if msgwindow
        cmds = []; ids = []; help = []
        
        # Si el filtro es *, mostrar solo movimientos compatibles
        if filter == "*"
          label = "[FILTRO: * (todos compatibles)]"
          cmds.push(label); ids.push(-1); help.push("Mostrando todos los movimientos compatibles")
          
          for m in all_moves
            if natural_moves.include?(m[0])
              cmds.push("* " + m[1]); ids.push(m[0]); help.push(pbGetMoveHelp_FINAL(m[0]))
            end
          end
        else
          label = filter == "" ? "[BUSCADOR: ...]" : ("[FILTRO: " + filter + "]")
          cmds.push(label); ids.push(-1); help.push("Escribe para filtrar por nombre o descripción. Escribe * para ver todos los compatibles.")
          for m in all_moves
            desc = pbGetMoveHelp_FINAL(m[0])
            if filter == "" || m[1].downcase.include?(filter.downcase) || desc.downcase.include?(filter.downcase)
              pre = natural_moves.include?(m[0]) ? "* " : "  "
              cmds.push(pre + m[1]); ids.push(m[0]); help.push(desc)
            end
          end
        end
        
        idx = Kernel.pbShowCommandsWithHelp(msgwindow, cmds, help, -1)
        return 0 if idx < 0
        sel_id = ids[idx]
        if sel_id == -1
          filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
        else
          return sel_id
        end
      rescue
        # Si algo falla, devolver 0
        return 0
      end
    end
  end

  def pbChooseSpeciesAdvanced_FINAL(msgwindow=nil)
    all_species = []
    for i in 1...PBSpecies.maxValue
      begin
        name = PBSpecies.getName(i)
        if name && name != ""
          all_species.push([i, name])
        end
      rescue
        next
      end
    end
    
    # Ordenar por número de Pokédex (no alfabéticamente)
    all_species.sort! { |a, b| a[0] <=> b[0] }
    filter = ""
    loop do
      msgwindow.visible = true if msgwindow
      cmds = []; ids = []; help = []
      
      if filter == ""
        label = "[BUSCADOR: ...]"
        cmds.push(label); ids.push(-1); help.push("Escribe para filtrar por nombre o número de Pokédex.")
      else
        # Verificar si es un número
        if filter =~ /^\d+$/
          # Convertir a número y buscar coincidencia exacta o parcial
          filter_num = filter.to_i
          label = "[FILTRO: #" + filter + "]"
          cmds.push(label); ids.push(-1); help.push("Buscando por número de Pokédex.")
        else
          label = "[FILTRO: " + filter + "]"
          cmds.push(label); ids.push(-1); help.push("Buscando por nombre.")
        end
      end
      
      for s in all_species
        # Buscar por número o nombre
        include_species = false
        if filter =~ /^\d+$/  # Es número
          # Búsqueda mejorada por número
          filter_num = filter.to_i
          # Coincidencia exacta o parcial del número
          include_species = s[0] == filter_num || s[0].to_s.include?(filter)
        else  # Es nombre
          include_species = s[1].downcase.include?(filter.downcase)
        end
        
        if filter == "" || include_species
          # Formato: "001: Bulbasaur" (siempre 3 dígitos)
          display_text = sprintf("%03d: %s", s[0], s[1])
          cmds.push(display_text); ids.push(s[0]); help.push("")
        end
      end
      
      idx = Kernel.pbShowCommandsWithHelp(msgwindow, cmds, help, -1)
      return 0 if idx < 0
      sel_id = ids[idx]
      if sel_id == -1
        filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
      else
        return sel_id
      end
    end
  end

  # Menú desplegable para seleccionar formas - REEMPLAZA el selector numérico
  def pbChooseFormMenu_FINAL(pkmn)
    return nil if !pkmn
    
    species_name = PBSpecies.getName(pkmn.species) rescue "???"
    
    # Construir lista de opciones disponibles
    cmds = []
    form_data = []  # [form_id, sprite_only_flag]
    
    # Siempre mostrar "Normal"
    cmds.push("Normal (forma 0)")
    form_data.push([0, false])
    
    # Escaneo Dinámico de Megas y Formas Secretas (1 a 19)
    # 1 se suele considerar la Mega principal o Forma Variante
    # 2, 3... pueden ser Megas X/Y, Dinamax ocultas, u otras variantes del Fangame
    for i in 1..19
      has_form = false
      begin
        has_form = safe_check_bitmap_file([pkmn.species, 0, false, false, i])
      rescue
      end
      
      # Excepción de compatibilidad con Pokémon Essentials: 
      # a veces la mega 1 no tiene sprite pero tiene función
      if i == 1 && !has_form
        begin
          has_form = true if MultipleForms.hasFunction?(pkmn.species, "getMegaForm")
        rescue
        end
      end
      
      if has_form
        label = ""
        
        # 1. Intentar obtener el nombre oficial del PBS
        begin
          n = pbGetMessage(MessageTypes::FormNames, pkmn.species)
          if n && n.strip != ""
            arr = n.split(",")
            label = arr[i].strip if arr[i] && arr[i].strip != ""
          end
        rescue
        end
        
        # 2. Respaldo inteligente si no hay nombre definido
        if label == ""
          if pkmn.species == 6 || pkmn.species == 150 # Charizard / Mewtwo
            label = "Mega X" if i == 1
            label = "Mega Y" if i == 2
          elsif i == 1
            has_mega = false
            begin; has_mega = MultipleForms.hasFunction?(pkmn.species, "getMegaForm"); rescue; end
            label = has_mega ? "Mega Evolución" : "Forma Alternativa (Regional/Variante)"
          else
            label = "Forma #{i}"
          end
        end
        
        cmds.push("#{label} (con estadísticas)")
        form_data.push([i, false])
        
        cmds.push("#{label} (solo sprite, sin stats)")
        form_data.push([i, true])
      end
    end
    
    # Detectar formas regionales (Alola 20-29, Galar 30-39, Hisui 40-49)
    regional_ranges = [
      [20, 29, "Alola"],
      [30, 39, "Galar"],
      [40, 49, "Hisui"]
    ]
    
    regional_ranges.each do |start_id, end_id, region|
      for i in start_id..end_id
        begin
          if safe_check_bitmap_file([pkmn.species, 0, false, false, i])
            n = pbGetMessage(MessageTypes::FormNames, pkmn.species).split(",")[i] rescue nil
            label = n && n.strip != "" ? n.strip : "#{region}"
            cmds.push("#{region}: #{label}")
            form_data.push([i, false])
            break  # Solo mostrar la primera forma de cada región
          end
        rescue
        end
      end
    end
    # Mostrar el menú
    title = "Seleccionar forma para #{species_name}"
    
    idx = Kernel.pbMessage(title, cmds, -1)
    
    # Si canceló, devolver nil
    return nil if idx < 0
    
    # Obtener datos de la forma seleccionada
    selected = form_data[idx]
    form_id = selected[0]
    sprite_only = selected[1]
    
    # Establecer el flag en el Pokémon
    pkmn.instance_variable_set(:@form_sprite_only_final, sprite_only) rescue nil
    
    # Establecer la forma real del Pokémon
    pkmn.form = form_id
    
    # Guardar forma persistente para mantenerla después del combate
    pkmn.instance_variable_set(:@persistent_form, form_id) rescue nil
    
    # Forzar el recalculo de Stats
    pkmn.calcStats
    
    # Truco para forzar la actualización de la UI del motor de Essentials:
    # Si la forma nueva es la misma numéricamente (ej. pasar de Mega con stats a Mega sin stats),
    # falseamos en secreto la variable de forma para obligar al juego a repintar la pantalla y recalcular todo.
    if pkmn.form == form_id
      pkmn.instance_variable_set(:@form, -1)
    end
    
    # Devolver el ID de forma
    return form_id
  end

  module_function :pbChooseFormMenu_FINAL
end

# --- CORE INJECTION ---
module Graphics
  class << self
    unless method_defined?(:old_upd_final)
      alias old_upd_final update
    end
    def update
      old_upd_final
      
      # Overrides en cada ciclo si es necesario
      if defined?(PokeBattle_Pokemon) && !@init_final
        @init_final = true
        $DEBUG=false; $_debug_pkmn=nil
        
        def Kernel.pbChooseTypeMenu_FINAL(pkmn)
          all_types = []
          for i in 0..PBTypes.maxValue
            begin
              name = PBTypes.getName(i)
              all_types.push([i, name]) if name && name != "" && !PBTypes.isPseudoType?(i)
            rescue; end
          end
          all_types.sort! { |a, b| a[1] <=> b[1] }
          
          # PASO 1: Slot (Acepta B para salir confirmando)
          t1_name = PBTypes.getName(pkmn.type1) rescue "???"
          t2_name = PBTypes.getName(pkmn.type2) rescue "???"
          msg = _INTL("Tipos: {1} / {2}\nSelecciona el slot a cambiar:", t1_name, t2_name)
          
          accion = Kernel.pbMessage(msg, [
            _INTL("Cambiar Tipo 1"),
            _INTL("Cambiar Tipo 2"),
            _INTL("Limpiar Tipos"),
            _INTL("Salir")
          ], 3)
          
          return if accion < 0 || accion == 3 # Salir
          
          if accion == 2
            pkmn.instance_variable_set(:@custom_type1, nil); pkmn.instance_variable_set(:@type1, nil) rescue nil
            pkmn.instance_variable_set(:@custom_type2, nil); pkmn.instance_variable_set(:@type2, nil) rescue nil
            pkmn.calcStats
            return
          end
          
          # PASO 2: Lista (Al elegir uno, guarda y sale de TODO)
          slot_label = accion == 0 ? "Tipo 1" : "Tipo 2"
          filter = ""
          loop do
            type_names = all_types.select { |t|
              filter == "" || t[1].downcase.include?(filter.downcase)
            }
            label = filter == "" ? "[BUSCADOR: ...]" : "[FILTRO: #{filter}]"
            cmds = [label] + type_names.map { |t| t[1] }
            ids  = [-1]    + type_names.map { |t| t[0] }
            
            ret = Kernel.pbMessage(_INTL("Elige el nuevo #{slot_label}:"), cmds, -1)
            
            return if ret < 0 # Pulsar B aquí también cierra todo confirmando lo anterior
            
            sel_id = ids[ret]
            if sel_id == -1
              filter = Kernel.pbMessageFreeText(_INTL("Buscar:"), filter, false, 20)
            else
              # GUARDAR Y SALIR DE GOLPE
              if accion == 0
                pkmn.instance_variable_set(:@custom_type1, sel_id); pkmn.instance_variable_set(:@type1, sel_id) rescue nil
              else
                pkmn.instance_variable_set(:@custom_type2, sel_id); pkmn.instance_variable_set(:@type2, sel_id) rescue nil
              end
              pkmn.calcStats
              return # Cierra el menú completo
            end
          end
        end

        def Kernel.pbChooseStatsMenu_FINAL(pkmn)
          return if !pkmn
          
          stats = [["HP", 0, "hp"], ["Ataque", 1, "attack"], ["Defensa", 2, "defense"], 
                   ["Ataque Especial", 4, "spatk"], ["Defensa Especial", 5, "spdef"], ["Velocidad", 3, "speed"]]
          
          loop do
            cmd = stats.map { |name, idx, var| _INTL("{1}: {2}", name, pkmn.send(var)) } + [_INTL("Salir")]
            choice = Kernel.pbMessage(_INTL("Selecciona un stat:"), cmd, -1)
            break if choice < 0 || choice == 6
            
            if choice < 6
              valor = pbMessageFreeText(_INTL("Nuevo {1}:", stats[choice][0]), pkmn.send(stats[choice][2]).to_s, false, 6)
              if valor && valor.match(/^\d+$/)
                if choice == 0
                  pkmn.hp = valor.to_i
                else
                  pkmn.iv[stats[choice][1]] = 31
                  pkmn.ev[stats[choice][1]] = 252
                  pkmn.instance_variable_set("@#{stats[choice][2]}".to_sym, valor.to_i)
                end
                Kernel.pbMessage(_INTL("{1} cambiado a {2}", stats[choice][0], valor))
              end
            end
          end
        end


        Object.class_eval <<-'CODE'
          class PokeBattle_Pokemon
            unless method_defined?(:old_abil_hack)
              alias old_abil_hack ability
              def ability
                return @abilityflag if @abilityflag && @abilityflag > 10
                
                # Excepcion Mewtwo Megas (Habilidad)
                if self.species == 150 && !@form_sprite_only_final
                  return (getID(PBAbilities,:STEADFAST) rescue 0) if @form == 1
                  return (getID(PBAbilities,:INSOMNIA) rescue 0) if @form == 2
                end
                
                if @form_sprite_only_final
                  o=@form; @form=0; r=MultipleForms.call("ability", self) rescue nil
                  r=self.__mf_ability if r.nil?; @form=o; return r
                end
                old_abil_hack
              end
            end
            def baseStats
              # Excepcion Mewtwo Megas (Stats)
              if self.species == 150 && !@form_sprite_only_final
                return [106,190,100,130,154,100] if @form == 1
                return [106,150,70,140,194,120] if @form == 2
              end
              frm=@form_sprite_only_final ? 0 : @form; o=@form; @form=frm; r=MultipleForms.call("getBaseStats", self); r=__mf_baseStats if r.nil?; @form=o; return r
            end
            def type1
              return @custom_type1 if @custom_type1
              frm=@form_sprite_only_final ? 0 : @form; o=@form; @form=frm; r=MultipleForms.call("type1", self); r=__mf_type1 if r.nil?; @form=o; return r
            end
            def type2
              return @custom_type2 if @custom_type2
              # Excepcion Mewtwo Mega X (Lucha)
              if self.species == 150 && !@form_sprite_only_final && @form == 1
                return (getID(PBTypes,:FIGHTING) rescue __mf_type2)
              end
              frm=@form_sprite_only_final ? 0 : @form; o=@form; @form=frm; r=MultipleForms.call("type2", self); r=__mf_type2 if r.nil?; @form=o; return r
            end
            def weight
              # Excepcion Mewtwo Megas (Peso)
              if self.species == 150 && !@form_sprite_only_final
                return 1270 if @form == 1
                return 330 if @form == 2
              end
              frm=@form_sprite_only_final ? 0 : @form; o=@form; @form=frm; r=MultipleForms.call("weight", self); r=__mf_weight if r.nil?; @form=o; return r
            end
            def height
              # Excepcion Mewtwo Megas (Altura)
              if self.species == 150 && !@form_sprite_only_final
                return 23 if @form == 1
                return 15 if @form == 2
              end
              frm=@form_sprite_only_final ? 0 : @form; o=@form; @form=frm; r=MultipleForms.call("height", self); r=__mf_height if r.nil?; @form=o; return r
            end
            
            # Hook para mantener forma persistente
            alias old_calcStats calcStats
            def calcStats(*args)
              persistent = @persistent_form rescue nil
              old_calcStats(*args)
              if persistent && @form != persistent
                @form = persistent
              end
            end

            # --- AMPLIACIÓN A 8 MOVIMIENTOS ---
            unless method_defined?(:old_init_moves)
              alias old_init_moves initialize
              def initialize(species, level, player=nil, withMoves=true)
                old_init_moves(species, level, player, false) # Inicializar sin movimientos primero
                if withMoves
                  begin
                    atkdata = pbRgssOpen("Data/attacksRS.dat", "rb")
                    offset = atkdata.getOffset(species - 1)
                    length = atkdata.getLength(species - 1) >> 1
                    atkdata.pos = offset
                    movelist = []
                    for i in 0..length - 1
                      alevel = atkdata.fgetw
                      move = atkdata.fgetw
                      movelist.push(move) if alevel <= level
                    end
                    atkdata.close
                    movelist |= [] # Eliminar duplicados
                    
                    # Cargar hasta los últimos 8 movimientos conocidos
                    listend = movelist.length - 8
                    listend = 0 if listend < 0
                    @moves = []
                    j = 0
                    for i in listend...listend + 8
                      moveid = (i >= movelist.length) ? 0 : movelist[i]
                      @moves[j] = PBMove.new(moveid)
                      j += 1
                    end
                  rescue
                    # Fallback si falla la lectura de datos
                    @moves = []
                    8.times { @moves.push(PBMove.new(0)) }
                  end
                end
              end
            end

            def numMoves
              ret = 0
              for i in 0...8 # Ampliado a 8
                ret += 1 if @moves[i] && @moves[i].id != 0
              end
              return ret
            end

            def hasMove?(move)
              if move.is_a?(String) || move.is_a?(Symbol)
                move = getID(PBMoves, move)
              end
              for i in 0...8
                return true if @moves[i] && @moves[i].id == move
              end
              return false
            end

            def pbLearnMove(move)
              if move.is_a?(String) || move.is_a?(Symbol)
                move = getID(PBMoves, move)
              end
              return false if hasMove?(move)
              for i in 0...8
                if !@moves[i] || @moves[i].id == 0
                  @moves[i] = PBMove.new(move)
                  return true
                end
              end
              return false
            end

            def pbDeleteMoveAtIndex(index)
              return if index < 0 || index >= 8
              @moves[index] = PBMove.new(0)
              @moves.compact!
              @moves.push(PBMove.new(0)) while @moves.length < 8
            end
          end
          unless method_defined?(:pbCheckPokemonBitmapFiles_H)
            alias pbCheckPokemonBitmapFiles_H pbCheckPokemonBitmapFiles
            def pbCheckPokemonBitmapFiles(p); f=p[4].to_i rescue 0
              if f>100; p2=p.clone; p2[4]=(f%100).to_s; r=pbCheckPokemonBitmapFiles_H(p2); return r if r; end
              if p[0]==260 && $mega_shiny_toggle; p2=p.clone; p2[4]="1"; r=pbCheckPokemonBitmapFiles_H(p2); return r if r; end
              
              # Parche para Sprites Cruzados de Megas X e Y Shinies (Bug de archivos en Charizard)
              if p[3] == true && p[0] == 6
                if f == 1
                  p3 = p.clone; p3[4] = "2"
                  r = pbCheckPokemonBitmapFiles_H(p3)
                  return r if r
                elsif f == 2
                  p3 = p.clone; p3[4] = "1"
                  r = pbCheckPokemonBitmapFiles_H(p3)
                  return r if r
                end
              end
              pbCheckPokemonBitmapFiles_H(p)
            end
          end
          unless method_defined?(:pbCheckPokemonIconFiles_H)
            alias pbCheckPokemonIconFiles_H pbCheckPokemonIconFiles
            def pbCheckPokemonIconFiles(p, e=false); f=p[3].to_i rescue 0
              if f>100; p2=p.clone; p2[3]=(f%100).to_s; r=pbCheckPokemonIconFiles_H(p2, e); return r if r; end
              
              # Parche Mewtwo: Desfase de PC Icons (1=Armadura, 2=MegaX, 3=MegaY)
              if p[0] == 150 && !e
                if f == 1; p2=p.clone; p2[3]="2"; r=pbCheckPokemonIconFiles_H(p2, e); return r if r
                elsif f == 2; p2=p.clone; p2[3]="3"; r=pbCheckPokemonIconFiles_H(p2, e); return r if r; end
              end
              
              if p[0]==260 && $mega_shiny_toggle && !e; p2=p.clone; p2[3]="1"; r=pbCheckPokemonIconFiles_H(p2, e); return r if r; end
              
              pbCheckPokemonIconFiles_H(p, e)
            end
          end
        CODE
      end

      # --- CURACIÓN TOTAL (+) (ignora Nuzlocke, instalado post-carga) ---
      begin
        Object.class_eval do
          def pbDebugHealParty
            return if !$Trainer
            healed = 0
            $Trainer.party.each do |pkmn|
              next if !pkmn
              healed += 1
              begin; pkmn.hp = pkmn.totalhp if pkmn.respond_to?(:hp=) && pkmn.respond_to?(:totalhp); rescue; end
              begin; pkmn.healHP; rescue; end
              begin; pkmn.healStatus; rescue; end
              begin; pkmn.healPP; rescue; end
            end
            Audio.se_play("Audio/SE/expfull", 80, 100) rescue nil
            pbMessage(_INTL("Curación: Se curó a {1} Pokémon (Acceso Directo).", healed)) rescue nil
          end
          
          def pbDebugRareCandy
            return if !$Trainer || !$PokemonBag
            item_id = nil
            begin; item_id = :RARECANDY; rescue; end
            begin; item_id = getID(PBItems,:RARECANDY) if defined?(PBItems); rescue; end
            
            if item_id && $PokemonBag.pbStoreItem(item_id, 99)
              Audio.se_play("Audio/SE/expfull", 80, 100) rescue nil
              pbMessage(_INTL("¡Añadidos 99 Caramelos Raros (Acceso Directo)!")) rescue nil
            else
              pbMessage(_INTL("Tu mochila está llena o no se encontró el objeto.")) rescue nil
            end
          end
        end
        
        # Inyección directa de teclado Win32API para evitar el motor roto de Input del juego.
        if !defined?($HealKey_Hooked)
          $HealKey_Hooked = true
          Input.class_eval do
            class << self
              unless method_defined?(:old_upd_heal)
                alias old_upd_heal update
                def update
                  old_upd_heal
                  $GetAsyncKeyState ||= Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
                  # 0xBB es el '+' (junto a Enter), 0x6B es el '+' numérico.
                  # 0xBD es el '-' (guion), 0x6D es el '-' numérico.
                  # & 0x01 detecta solo el "click" inicial para no spamearlo.
                  if ($GetAsyncKeyState.call(0xBB) & 0x01 == 1) || 
                     ($GetAsyncKeyState.call(0x6B) & 0x01 == 1)
                    pbDebugHealParty
                  end
                  
                  if ($GetAsyncKeyState.call(0xBD) & 0x01 == 1) || 
                     ($GetAsyncKeyState.call(0x6D) & 0x01 == 1)
                    pbDebugRareCandy
                  end
                end
              end
            end
          end
        end
      rescue
      end

      Object.class_eval do
        # 1. pbChooseMoveList
        if !method_defined?(:pbChooseMoveList_F) && (respond_to?(:pbChooseMoveList, true) || Kernel.respond_to?(:pbChooseMoveList, true))
          begin; alias_method :pbChooseMoveList_F, :pbChooseMoveList
            def pbChooseMoveList(d=0); return pbChooseMoveAdvanced_FINAL($_debug_pkmn); end
          rescue; end
        end
        
        # 1.25. pbChooseAbilityList
        if !method_defined?(:pbChooseAbilityList_F) && (respond_to?(:pbChooseAbilityList, true) || Kernel.respond_to?(:pbChooseAbilityList, true))
          begin; alias_method :pbChooseAbilityList_F, :pbChooseAbilityList
            def pbChooseAbilityList(d=0); return pbChooseAbilitySelection_FINAL($_debug_pkmn); end
          rescue; end
        end
        
        # 1.5. pbChooseSpecies y pbChooseSpeciesOrdered
        if !method_defined?(:pbChooseSpecies_F) && (respond_to?(:pbChooseSpecies, true) || Kernel.respond_to?(:pbChooseSpecies, true))
          begin; alias_method :pbChooseSpecies_F, :pbChooseSpecies
            def pbChooseSpecies(d=0); return pbChooseSpeciesAdvanced_FINAL; end
          rescue; end
        end
        
        if !method_defined?(:pbChooseSpeciesOrdered_F) && (respond_to?(:pbChooseSpeciesOrdered, true) || Kernel.respond_to?(:pbChooseSpeciesOrdered, true))
          begin; alias_method :pbChooseSpeciesOrdered_F, :pbChooseSpeciesOrdered
            def pbChooseSpeciesOrdered(d=0); return pbChooseSpeciesAdvanced_FINAL; end
          rescue; end
        end
        
        # --- HOOK GLOBAL PARA APRENDER MOVIMIENTOS (8 SLOTS) ---
        if !method_defined?(:pbLearnMove_orig_8moves) && (respond_to?(:pbLearnMove, true) || Kernel.respond_to?(:pbLearnMove, true))
          begin
            alias pbLearnMove_orig_8moves pbLearnMove
            def pbLearnMove(pokemon, move, ignoreifknown=false, bymachine=false, &block)
              return if !pokemon || move <= 0
              # Si ya lo conoce, no hacer nada
              return if pokemon.hasMove?(move) && ignoreifknown
              
              # Si tiene espacio (menos de 8), aprender directamente
              if pokemon.numMoves < 8
                pokemon.pbLearnMove(move)
                movename = PBMoves.getName(move)
                Kernel.pbMessage(_INTL("{1} aprendió {2}!", pokemon.name, movename))
                return true
              end
              
              # Si tiene 8 movimientos, preguntar para olvidar uno
              movename = PBMoves.getName(move)
              Kernel.pbMessage(_INTL("{1} quiere aprender {2}, pero ya conoce 8 movimientos.", pokemon.name, movename))
              if Kernel.pbConfirmMessage(_INTL("¿Quieres olvidar un movimiento para aprender {1}?", movename))
                loop do
                  Kernel.pbMessage(_INTL("Selecciona un movimiento para olvidar."))
                  forgetmove = pbForgetMove_8moves(pokemon, move)
                  if forgetmove >= 0 && forgetmove < 8
                    oldmove = pokemon.moves[forgetmove].id
                    oldmovename = PBMoves.getName(oldmove)
                    pokemon.moves[forgetmove] = PBMove.new(move)
                    Kernel.pbMessage(_INTL("¡1, 2 y... puf! {1} olvidó {2}...", pokemon.name, oldmovename))
                    Kernel.pbMessage(_INTL("Y... ¡{1} aprendió {2}!", pokemon.name, movename))
                    return true
                  elsif Kernel.pbConfirmMessage(_INTL("¿Quieres dejar de aprender {1}?", movename))
                    Kernel.pbMessage(_INTL("{1} no aprendió {2}.", pokemon.name, movename))
                    return false
                  end
                end
              else
                Kernel.pbMessage(_INTL("{1} no aprendió {2}.", pokemon.name, movename))
                return false
              end
            end
          rescue
          end
        end
        # Helper para abrir la pantalla de olvido (Resumen completo)
        def pbForgetMove_8moves(pokemon, move)
          ret = -1
          # Deteccion robusta de clases segun la version de Essentials
          scene_class = (defined?(PokemonSummaryScene) ? PokemonSummaryScene : (defined?(PokemonSummary_Scene) ? PokemonSummary_Scene : nil))
          screen_class = (defined?(PokemonSummaryScreen) ? PokemonSummaryScreen : (defined?(PokemonSummary_Screen) ? PokemonSummary_Screen : (defined?(PokemonSummary) ? PokemonSummary : nil)))
          
          if !scene_class || !screen_class
            # Fallback a mensaje si no se encuentran las clases de la UI
            commands = []
            for i in 0...8
              m = pokemon.moves[i]
              commands.push(m && m.id > 0 ? PBMoves.getName(m.id) : "[VACÍO]")
            end
            commands.push("Cancelar")
            return Kernel.pbMessage(_INTL("¿Qué movimiento debe olvidar?"), commands, 8)
          end

          pbFadeOutIn(99999) {
            scene = scene_class.new
            screen = screen_class.new(scene)
            ret = screen.pbStartForgetScreen([pokemon], 0, move)
          }
          return ret
        end
      end

      # --- UI: RESUMEN CON 8 MOVIMIENTOS (MULTIPÁGINA) ---
      if defined?(MoveSelectionSprite)
        MoveSelectionSprite.class_eval do
          def refresh
            w = @movesel.width
            h = @movesel.height / 2
            self.x = 240
            # Usar un índice relativo para el dibujo (0 a 3 o 0 a 4 si hay 5º move)
            # Pero en mi lógica de scroll, el sprite siempre se posiciona en 0-4
            display_index = self.index
            # Si estamos en modo scroll, el index real puede ser 0-7, 
            # pero el sprite solo se mueve en las 4 posiciones visibles.
            # Sin embargo, mi drawMoveSelection actual dibuja 5 slots.
            
            # Ajuste dinámico de posición Y
            row = self.index % 4
            row = 4 if self.index == 8 # Movimiento nuevo
            
            self.y = 92 + (row * 64)
            self.y -= 76 if @fifthmove
            self.y += 20 if @fifthmove && self.index == 8 # El nuevo move va abajo
            
            self.bitmap = @movesel.bitmap
            if self.preselected
              self.src_rect.set(0, h, w, h)
            else
              self.src_rect.set(0, 0, w, h)
            end
          end
        end
      end

      if defined?(PokemonSummaryScene)
        PokemonSummaryScene.class_eval do
          # --- NO SOBRESCRIBIR drawPageThree NI drawPageFour ---
          # Las dejamos para el juego base (Stats y Memo)
          
          # Página de movimientos 1-4 (NUEVA)
          def drawPageMoves1(pokemon)
            return if !pokemon
            overlay = @sprites["overlay"].bitmap
            overlay.clear
            @sprites["background"].setBitmap("Graphics/Pictures/summary4")
            @sprites["pokemon"].visible = true if @sprites["pokemon"]
            @sprites["pokeicon"].visible = false if @sprites["pokeicon"]
            imagepos = []
            if pbPokerus(pokemon) == 1 || pokemon.hp == 0 || pokemon.status > 0
              status = 8 if pbPokerus(pokemon) == 1
              status = pokemon.status - 1 if pokemon.status > 0
              status = 7 if pokemon.hp == 0
              imagepos.push(["Graphics/Pictures/statuses", 124, 100, 0, 16 * status, 44, 16])
            end
            if pokemon.isShiny?
              imagepos.push([sprintf("Graphics/Pictures/shiny"), 2, 134, 0, 0, -1, -1])
            end
            if pbPokerus(pokemon) == 2
              imagepos.push([sprintf("Graphics/Pictures/summaryPokerus"), 176, 100, 0, 0, -1, -1])
            end
            ballused = pokemon.ballused ? pokemon.ballused : 0
            ballimage = sprintf("Graphics/Pictures/summaryball%02d", pokemon.ballused)
            imagepos.push([ballimage, 14, 60, 0, 0, -1, -1])
            pbDrawImagePositions(overlay, imagepos)
            base = Color.new(248, 248, 248)
            shadow = Color.new(104, 104, 104)
            pbSetSystemFont(overlay)
            pokename = pokemon.name
            textpos = [
              [_INTL("MOVIMIENTOS 1"), 26, 16, 0, base, shadow],
              [pokename, 46, 62, 0, base, shadow],
              [pokemon.level.to_s, 46, 92, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)],
              [_INTL("Objeto"), 16, 320, 0, base, shadow]
            ]
            if pokemon.hasItem?
              textpos.push([PBItems.getName(pokemon.item), 16, 352, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
            else
              textpos.push([_INTL("Ninguno"), 16, 352, 0, Color.new(184, 184, 160), Color.new(208, 208, 200)])
            end
            if pokemon.isMale?
              textpos.push([_INTL("♂"), 178, 62, 0, Color.new(24, 112, 216), Color.new(136, 168, 208)])
            elsif pokemon.isFemale?
              textpos.push([_INTL("♀"), 178, 62, 0, Color.new(248, 56, 32), Color.new(224, 152, 144)])
            end
            
            imagepos = []
            yPos = 98
            for i in 0...4 # Solo primeros 4
              move = pokemon.moves[i]
              if move && move.id > 0
                imagepos.push(["Graphics/Pictures/types", 248, yPos + 2, 0, move.type * 28, 64, 28])
                textpos.push([PBMoves.getName(move.id), 316, yPos, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                if move.totalpp > 0
                  textpos.push([_ISPRINTF("PP"), 342, yPos + 32, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                  textpos.push([sprintf("%d/%d", move.pp, move.totalpp), 460, yPos + 32, 1, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                end
              else
                textpos.push(["-", 316, yPos, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                textpos.push(["--", 442, yPos + 32, 1, Color.new(64, 64, 64), Color.new(176, 176, 176)])
              end
              yPos += 64
            end
            pbDrawTextPositions(overlay, textpos)
            pbDrawImagePositions(overlay, imagepos)
            drawMarkings(overlay, 15, 291, 72, 20, pokemon.markings)
          end

          # Página de movimientos 5-8 (NUEVA)
          def drawPageMoves2(pokemon)
            return if !pokemon
            overlay = @sprites["overlay"].bitmap
            overlay.clear
            @sprites["background"].setBitmap("Graphics/Pictures/summary4")
            @sprites["pokemon"].visible = true if @sprites["pokemon"]
            @sprites["pokeicon"].visible = false if @sprites["pokeicon"]
            imagepos = []
            if pbPokerus(pokemon) == 1 || pokemon.hp == 0 || pokemon.status > 0
              status = 8 if pbPokerus(pokemon) == 1
              status = pokemon.status - 1 if pokemon.status > 0
              status = 7 if pokemon.hp == 0
              imagepos.push(["Graphics/Pictures/statuses", 124, 100, 0, 16 * status, 44, 16])
            end
            if pokemon.isShiny?
              imagepos.push([sprintf("Graphics/Pictures/shiny"), 2, 134, 0, 0, -1, -1])
            end
            if pbPokerus(pokemon) == 2
              imagepos.push([sprintf("Graphics/Pictures/summaryPokerus"), 176, 100, 0, 0, -1, -1])
            end
            ballused = pokemon.ballused ? pokemon.ballused : 0
            ballimage = sprintf("Graphics/Pictures/summaryball%02d", pokemon.ballused)
            imagepos.push([ballimage, 14, 60, 0, 0, -1, -1])
            pbDrawImagePositions(overlay, imagepos)
            base = Color.new(248, 248, 248)
            shadow = Color.new(104, 104, 104)
            pbSetSystemFont(overlay)
            pokename = pokemon.name
            textpos = [
              [_INTL("MOVIMIENTOS 2"), 26, 16, 0, base, shadow],
              [pokename, 46, 62, 0, base, shadow],
              [pokemon.level.to_s, 46, 92, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)],
              [_INTL("Objeto"), 16, 320, 0, base, shadow]
            ]
            if pokemon.hasItem?
              textpos.push([PBItems.getName(pokemon.item), 16, 352, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
            else
              textpos.push([_INTL("Ninguno"), 16, 352, 0, Color.new(184, 184, 160), Color.new(208, 208, 200)])
            end
            if pokemon.isMale?
              textpos.push([_INTL("♂"), 178, 62, 0, Color.new(24, 112, 216), Color.new(136, 168, 208)])
            elsif pokemon.isFemale?
              textpos.push([_INTL("♀"), 178, 62, 0, Color.new(248, 56, 32), Color.new(224, 152, 144)])
            end
            
            imagepos = []
            yPos = 98
            for i in 4...8 # Movimientos 5, 6, 7, 8
              move = pokemon.moves[i]
              if move && move.id > 0
                imagepos.push(["Graphics/Pictures/types", 248, yPos + 2, 0, move.type * 28, 64, 28])
                textpos.push([PBMoves.getName(move.id), 316, yPos, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                if move.totalpp > 0
                  textpos.push([_ISPRINTF("PP"), 342, yPos + 32, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                  textpos.push([sprintf("%d/%d", move.pp, move.totalpp), 460, yPos + 32, 1, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                end
              else
                textpos.push(["-", 316, yPos, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
                textpos.push(["--", 442, yPos + 32, 1, Color.new(64, 64, 64), Color.new(176, 176, 176)])
              end
              yPos += 64
            end
            pbDrawTextPositions(overlay, textpos)
            pbDrawImagePositions(overlay, imagepos)
            drawMarkings(overlay, 15, 291, 72, 20, pokemon.markings)
          end

          # Sobrescribir el bucle de la escena para añadir la página extra
          def pbScene
            pbPlayCry(@pokemon)
            loop do
              Graphics.update
              Input.update
              pbUpdate
              if Input.trigger?(Input::B); break; end
              if Input.trigger?(Input::C)
                if @page == 2
                  Habilidades(@pokemon) rescue nil
                  dorefresh = true
                elsif @page == 3 || @page == 4
                  pbMoveSelection
                  dorefresh = true
                end
              end

              dorefresh = false
              if Input.trigger?(Input::UP) && @partyindex > 0
                oldindex = @partyindex
                pbGoToPrevious
                if @partyindex != oldindex
                  @pokemon = @party[@partyindex]
                  @sprites["pokemon"].setPokemonBitmap(@pokemon)
                  @sprites["pokemon"].color = Color.new(0,0,0,0)
                  pbPositionPokemonSprite(@sprites["pokemon"], 40, 144)
                  dorefresh = true
                  pbPlayCry(@pokemon)
                end
              end
              if Input.trigger?(Input::DOWN) && @partyindex < @party.length - 1
                oldindex = @partyindex
                pbGoToNext
                if @partyindex != oldindex
                  @pokemon = @party[@partyindex]
                  @sprites["pokemon"].setPokemonBitmap(@pokemon)
                  @sprites["pokemon"].color = Color.new(0,0,0,0)
                  pbPositionPokemonSprite(@sprites["pokemon"], 40, 144)
                  dorefresh = true
                  pbPlayCry(@pokemon)
                end
              end
              if Input.trigger?(Input::LEFT) && !@pokemon.isEgg?
                oldpage = @page
                @page -= 1
                @page = 5 if @page < 0
                dorefresh = true
                if @page != oldpage; pbPlayCursorSE(); dorefresh = true; end
              end
              if Input.trigger?(Input::RIGHT) && !@pokemon.isEgg?
                oldpage = @page
                @page += 1
                @page = 0 if @page > 5
                dorefresh = true
                if @page != oldpage; pbPlayCursorSE(); dorefresh = true; end
              end
              
              if dorefresh
                case @page
                when 0; drawPageOne(@pokemon)
                when 1; drawPageTwo(@pokemon)
                when 2; drawPageThree(@pokemon) # Stats original
                when 3; drawPageMoves1(@pokemon) # Movimientos 1-4
                when 4; drawPageMoves2(@pokemon) # Movimientos 5-8
                when 5; drawPageFive(@pokemon) rescue nil # Cintas original
                end
              end
            end
            return @partyindex
          end

          # Actualizar dibujo de selección con scroll de 4 en 4
          def drawMoveSelection(pokemon, moveToLearn)
            overlay = @sprites["overlay"].bitmap
            overlay.clear
            base = Color.new(64, 64, 64)
            shadow = Color.new(176, 176, 176)
            
            # Definir constantes locales por si no están definidas globalmente
            m_pp = 1; m_pwr = 2; m_cat = 3; m_acc = 4
            
            # Usar el fondo correcto según si estamos aprendiendo o solo viendo
            bg_path = (moveToLearn != 0) ? "Graphics/Pictures/summary4learning" : "Graphics/Pictures/summary4details"
            @sprites["background"].setBitmap(bg_path)
            
            pbSetSystemFont(overlay)
            textpos = [
              [_INTL("MOVIMIENTOS"), 26, 16, 0, Color.new(248,248,248), Color.new(104,104,104)],
              [_INTL("CATEGORÍA"), 16, 122, 0, Color.new(248,248,248), Color.new(104,104,104)],
              [_INTL("POTENCIA"), 16, 154, 0, Color.new(248,248,248), Color.new(104,104,104)],
              [_INTL("PRECISIÓN"), 16, 186, 0, Color.new(248,248,248), Color.new(104,104,104)]
            ]
            
            imagepos = []
            # Ajustamos yPos inicial: 18 para aprendizaje (5 slots), 98 para normal (4 slots)
            yPos = (moveToLearn != 0) ? 18 : 98
            
            # Rango de movimientos a mostrar (0-3 o 4-7)
            # Solo actualizamos @move_scroll si NO estamos seleccionando el nuevo move (8)
            # Esto permite ver el nuevo move desde cualquier pestaña sin saltar.
            if @sprites["movesel"].index != 8
              @move_scroll = (@sprites["movesel"].index >= 4) ? 4 : 0
            end
            
            for i in 0...4
              idx = i + @move_scroll
              moveobject = pokemon.moves[idx]
              
              if moveobject && moveobject.id != 0
                imagepos.push(["Graphics/Pictures/types", 248, yPos + 6, 0, moveobject.type * 28, 64, 28])
                textpos.push([PBMoves.getName(moveobject.id), 316, yPos + 4, 0, base, shadow])
                if moveobject.totalpp > 0
                  textpos.push([_ISPRINTF("PP"), 342, yPos + 34, 0, base, shadow])
                  textpos.push([sprintf("%d/%d", moveobject.pp, moveobject.totalpp), 460, yPos + 34, 1, base, shadow])
                end
              else
                textpos.push(["-", 316, yPos + 4, 0, base, shadow])
                textpos.push(["--", 442, yPos + 34, 1, base, shadow])
              end
              yPos += 64
            end
            
            # Dibujar el nuevo movimiento a aprender
            if moveToLearn != 0
              # Ajustar posición para que coincida con las líneas blancas del fondo (nudge up a 296)
              yPos = 296
              moveData = PBMove.new(moveToLearn)
              imagepos.push(["Graphics/Pictures/types", 248, yPos + 6, 0, moveData.type * 28, 64, 28])
              textpos.push([PBMoves.getName(moveData.id), 316, yPos + 4, 0, base, shadow])
              textpos.push([_ISPRINTF("PP"), 342, yPos + 34, 0, base, shadow])
              md = PBMoveData.new(moveToLearn) rescue nil
              totalpp = md ? md.totalpp : 35
              textpos.push([sprintf("%d/%d", totalpp, totalpp), 460, yPos + 34, 1, base, shadow])
            end
            
            pbDrawTextPositions(overlay, textpos)
            pbDrawImagePositions(overlay, imagepos)
          end

          def drawSelectedMove(pokemon, moveToLearn, moveid)
            overlay = @sprites["overlay"].bitmap
            base = Color.new(64, 64, 64)
            shadow = Color.new(176, 176, 176)
            @sprites["pokemon"].visible = false if @sprites["pokemon"]
            @sprites["pokeicon"].visible = true if @sprites["pokeicon"]
            
            textpos = []
            if moveid && moveid > 0
              # USAR PBMoveData QUE ES LO QUE USA EL MOTOR ORIGINAL
              md = PBMoveData.new(moveid) rescue nil
              if md
                pwr = md.basedamage
                acc = md.accuracy
                cat = md.category
              else
                pwr = 0; acc = 0; cat = 2
              end
              
              pwr_str = (pwr > 0) ? pwr.to_s : "---"
              acc_str = (acc > 0) ? acc.to_s : "---"
              
              textpos.push([pwr_str, 210, 154, 1, base, shadow])
              textpos.push([acc_str, 210, 186, 1, base, shadow])
              # Descripción
              desc = pbGetMessage(MessageTypes::MoveDescriptions, moveid) rescue ""
              drawTextEx(overlay, 4, 218, 230, 5, desc, base, shadow) if desc && desc != ""
              # Categoría - Mover un pelín más a la derecha (162)
              begin
                imagepos = [["Graphics/Pictures/category", 162, 124, 0, (cat || 2) * 28, 64, 28]]
                pbDrawImagePositions(overlay, imagepos)
              rescue; end
            end
            pbDrawTextPositions(overlay, textpos)
          end

          def pbChooseMoveToForget(moveToLearn)
            selmove = 0
            ret = 0
            # Crear lista de slots validos: movimientos actuales + el nuevo (8)
            valid_slots = []
            for i in 0...8
              valid_slots.push(i) if @pokemon.moves[i] && @pokemon.moves[i].id > 0
            end
            valid_slots.push(8) if moveToLearn > 0
            
            v_idx = 0 # Indice dentro de valid_slots
            selmove = valid_slots[v_idx]
            
            @page = 3 # Empezar siempre en la página de movimientos (página 4 real)
            
            # REFRESCO INICIAL PARA EVITAR PANTALLA NEGRA
            case @page
            when 3; drawPageMoves1(@pokemon)
            when 4; drawPageMoves2(@pokemon)
            end
            drawMoveSelection(@pokemon, moveToLearn)
            initial_moveid = (selmove == 8) ? moveToLearn : @pokemon.moves[selmove].id
            drawSelectedMove(@pokemon, moveToLearn, initial_moveid)
            
            loop do
              Graphics.update
              Input.update
              pbUpdate
              if Input.trigger?(Input::B); ret = 8; break; end
              if Input.trigger?(Input::C) && (@page == 3 || @page == 4); ret = selmove; break; end
              
              moving = false
              if Input.trigger?(Input::DOWN)
                if selmove == 8
                  selmove = (@page == 3) ? 0 : 4
                elsif (selmove == 3 && @page == 3) || (selmove == 7 && @page == 4)
                  selmove = 8
                else
                  # Intentar mover al siguiente si existe
                  test_move = selmove + 1
                  if @pokemon.moves[test_move] && @pokemon.moves[test_move].id > 0
                    selmove = test_move
                  else
                    selmove = 8
                  end
                end
                moving = true
              elsif Input.trigger?(Input::UP)
                if selmove == 8
                  # Ir al último válido de la página actual
                  if @page == 3
                    selmove = 3
                  else
                    # Buscar último válido en 4-7
                    selmove = 4
                    for i in 4..7
                      selmove = i if @pokemon.moves[i] && @pokemon.moves[i].id > 0
                    end
                  end
                elsif (selmove == 0 && @page == 3) || (selmove == 4 && @page == 4)
                  selmove = 8
                else
                  selmove -= 1
                end
                moving = true
              elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
                # Cambiar de "Pestaña" (Moves 1 <-> Moves 2)
                @page = (@page == 3) ? 4 : 3
                if selmove != 8
                  # Intentar mantener la misma posición visual (0-3 <-> 4-7)
                  new_sel = (selmove < 4) ? selmove + 4 : selmove - 4
                  if @pokemon.moves[new_sel] && @pokemon.moves[new_sel].id > 0
                    selmove = new_sel
                  else
                    # Si no existe el equivalente, buscar el primer válido de la página
                    selmove = (@page == 3) ? 0 : 4
                    # (Si la pág 4 está vacía, selmove volverá a 8 o se quedará en el primero)
                  end
                end
                moving = true
              end
              
              if moving
                @sprites["movesel"].index = selmove
                # Forzar @move_scroll según selmove o página forzada
                if selmove == 8
                   @move_scroll = (@page == 4) ? 4 : 0
                else
                   @move_scroll = (selmove >= 4) ? 4 : 0
                   @page = (selmove >= 4) ? 4 : 3 # Sincronizar pág si nos movemos por flechas
                end
                
                pbPlayCursorSE()
                case @page
                when 3; drawPageMoves1(@pokemon); @move_scroll = 0
                when 4; drawPageMoves2(@pokemon); @move_scroll = 4
                end
                
                @sprites["movesel"].visible = true
                drawMoveSelection(@pokemon, moveToLearn)
                new_m_id = (selmove == 8) ? moveToLearn : @pokemon.moves[selmove].id
                drawSelectedMove(@pokemon, moveToLearn, new_m_id)
              end
            end
            return (ret == 8) ? -1 : ret
          end

          def pbMoveSelection
            @sprites["movesel"].visible = true
            # Empezar en el primer move de la página actual
            selmove = (@page == 4) ? 4 : 0
            @sprites["movesel"].index = selmove
            switching = false
            oldselmove = 0
            drawMoveSelection(@pokemon, 0)
            drawSelectedMove(@pokemon, 0, @pokemon.moves[selmove].id)
            loop do
              Graphics.update
              Input.update
              pbUpdate
              if Input.trigger?(Input::B)
                break if !switching
                @sprites["movepresel"].visible = false
                switching = false
              end
              if Input.trigger?(Input::C)
                if !(@pokemon.isShadow? rescue false)
                  if !switching
                    @sprites["movepresel"].index = selmove
                    oldselmove = selmove
                    @sprites["movepresel"].visible = true
                    switching = true
                  else
                    tmpmove = @pokemon.moves[oldselmove]
                    @pokemon.moves[oldselmove] = @pokemon.moves[selmove]
                    @pokemon.moves[selmove] = tmpmove
                    @sprites["movepresel"].visible = false
                    switching = false
                    drawMoveSelection(@pokemon, 0)
                    m = @pokemon.moves[selmove]
                    drawSelectedMove(@pokemon, 0, m ? m.id : 0)
                  end
                end
              end
              
              moving = false
              if Input.trigger?(Input::DOWN)
                selmove = (selmove + 1) % 8
                moving = true
              elsif Input.trigger?(Input::UP)
                selmove = (selmove - 1) % 8
                moving = true
              elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
                # Saltar entre "Pestañas" (Pág 3 <-> Pág 4)
                selmove = (selmove < 4) ? selmove + 4 : selmove - 4
                moving = true
              end

              if moving
                @sprites["movesel"].index = selmove
                # Sincronizar @page según el move actual para que al salir estemos en la página correcta
                @page = (selmove >= 4) ? 4 : 3
                drawMoveSelection(@pokemon, 0)
                m = @pokemon.moves[selmove]
                drawSelectedMove(@pokemon, 0, m ? m.id : 0)
                pbPlayCursorSE()
              end
            end
            @sprites["movesel"].visible = false
            # Al salir, asegurar que el fondo y contenido coinciden con la página final
            if @page == 3
              drawPageMoves1(@pokemon)
            else
              drawPageMoves2(@pokemon)
            end
          end
        end
      end

      # Hook para Kernel.pbMessageChooseNumber - REEMPLAZA el selector numérico por menú
      # Se instala después de que los scripts del juego estén cargados
      if !defined?($form_menu_hook_installed) || !$form_menu_hook_installed
        begin
          if Kernel.respond_to?(:pbMessageChooseNumber)
            Kernel.module_eval do
              class << self
                unless method_defined?(:pbMessageChooseNumber_orig_mfh)
                  alias :pbMessageChooseNumber_orig_mfh :pbMessageChooseNumber
                end
              end
              
              def self.pbMessageChooseNumber(message, params, *args, &block)
                txt = message.to_s.downcase rescue ""
                norm = txt.tr("áéíóúüñ", "aeiouun") rescue txt
                
                # El texto original es "Setear la forma del Pokémon."
                if norm.include?("setear la forma") || norm.include?("establecer la forma")
                  pkmn = $_debug_pkmn
                  pkmn = $last_debug_pkmn_final if !pkmn
                  
                  if pkmn
                    selected_form = Kernel.pbChooseFormMenu_FINAL(pkmn)
                    return pkmn.form if selected_form.nil?
                    return selected_form
                  end
                end
                
                Kernel.pbMessageChooseNumber_orig_mfh(message, params, *args, &block)
              end
            end
            $form_menu_hook_installed = true
          end
          # Indicadores de Eficacia Visual (Battle UI)
      if defined?(FightMenuButtons) && defined?(PokeBattle_Scene) && !@fight_menu_hook_installed
        @fight_menu_hook_installed = true
        Object.class_eval <<-'CODE'
          class PokeBattle_Scene
            unless method_defined?(:pbFightMenu_orig_eff_hook)
              alias pbFightMenu_orig_eff_hook pbFightMenu
            end
            def pbFightMenu(index)
              pbShowWindow(FIGHTBOX)
              cw = @sprites["fightwindow"]
              battler = @battle.battlers[index]
              cw.battler = battler
              $_fight_menu_battler = battler # Soporte para eficacia visual
              $_fight_menu_battle = @battle   # Soporte para eficacia visual
              lastIndex = @lastmove[index]
              # Asegurar que empezamos en la página correcta si el último índice fue > 3
              if lastIndex >= 4 && lastIndex < 8
                cw.page = 1
              else
                cw.page = 0
              end
              
              if lastIndex == 8
                cw.setIndex(8)
              elsif battler.moves[lastIndex] && battler.moves[lastIndex].id != 0
                cw.setIndex(lastIndex % 4)
              else
                cw.setIndex(0)
              end
              cw.megaButton = 0
              cw.megaButton = 1 if @battle.pbCanMegaEvolve?(index)
              pbSelectBattler(index)
              pbRefresh
              loop do
                pbGraphicsUpdate
                pbInputUpdate
                pbFrameUpdate(cw)
                if Input.trigger?(Input::LEFT) && cw.index != 8 && (cw.index & 1) == 1
                    pbPlayCursorSE() if cw.setIndex(cw.index - 1)
                elsif Input.trigger?(Input::RIGHT) && cw.index != 8 && (cw.index & 1) == 0
                    pbPlayCursorSE() if cw.setIndex(cw.index + 1)
                elsif Input.trigger?(Input::UP)
                  if cw.index == 0 || cw.index == 1
                    # Contar movimientos para ver si permitimos ir al botón de página
                    total_moves = 0
                    battler ||= @battle.battlers[index]
                    battler.moves.each { |m| total_moves += 1 if m && m.id > 0 }
                    if total_moves > 4
                      pbPlayCursorSE() if cw.setIndex(8) # Ir al botón MOV 2
                    end
                  elsif cw.index >= 2 && cw.index < 4
                    pbPlayCursorSE() if cw.setIndex(cw.index - 2)
                  end
                elsif Input.trigger?(Input::DOWN)
                  if cw.index == 8
                    pbPlayCursorSE() if cw.setIndex(0) # Volver al primer movimiento
                  elsif cw.index <= 1
                    pbPlayCursorSE() if cw.setIndex(cw.index + 2)
                  end
                end
                if Input.trigger?(Input::C)
                  if cw.index == 8
                    # CAMBIO DE PÁGINA
                    cw.page = (cw.page == 0) ? 1 : 0
                    cw.refresh
                    pbPlayDecisionSE()
                  else
                    pbPlayDecisionSE()
                    ret = cw.index + (cw.page * 4)
                    @lastmove[index] = ret
                    $_fight_menu_battler = nil
                    $_fight_menu_battle = nil
                    return ret
                  end
                elsif Input.trigger?(Input::A) # Mega Evolución
                  if @battle.pbCanMegaEvolve?(index)
                    @battle.pbRegisterMegaEvolution(index)
                    cw.megaButton = 2
                    pbPlayDecisionSE()
                  end
                elsif Input.trigger?(Input::B)
                  @lastmove[index] = (cw.index == 8) ? 0 : cw.index + (cw.page * 4)
                  $_fight_menu_battler = nil
                  $_fight_menu_battle = nil
                  pbPlayCancelSE()
                  return -1
                end
              end
            end
          end

          class PokeBattle_Battler
            unless method_defined?(:pbInitPokemon_orig_8move_hook)
              alias pbInitPokemon_orig_8move_hook pbInitPokemon
            end
            def pbInitPokemon(pkmn, pkmnIndex)
              pbInitPokemon_orig_8move_hook(pkmn, pkmnIndex)
              # Ampliamos a 8 movimientos
              @moves = []
              for i in 0...8
                if pkmn.moves[i] && pkmn.moves[i].id > 0
                  @moves[i] = PokeBattle_Move.pbFromPBMove(@battle, pkmn.moves[i])
                else
                  @moves[i] = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(0))
                end
              end
            end
          end

          class FightMenuDisplay
            attr_accessor :page

            unless method_defined?(:initialize_orig_8move_hook)
              alias initialize_orig_8move_hook initialize
            end
            def initialize(battler, viewport=nil)
              @page = 0
              initialize_orig_8move_hook(battler, viewport)
            end

            unless method_defined?(:setIndex_orig_eff_hook)
              alias setIndex_orig_eff_hook setIndex
            end
            def setIndex(value)
              if value == 8
                @index = 8
                refresh
                return true
              end
              return setIndex_orig_eff_hook(value)
            end

            unless method_defined?(:refresh_orig_8move_hook)
              alias refresh_orig_8move_hook refresh
            end
            def refresh
              return if !@battler
              
              # SINCRONIZACIÓN AGRESIVA PARA EVITAR DATOS OBSOLETOS
              if @battler.pokemon && @battler.pokemon.moves && (@battler.moves.length < 8 || !@battler.moves[4])
                # Re-sincronizar los 8 movimientos desde el objeto Pokemon
                for i in 0...8
                  pkmn_m = @battler.pokemon.moves[i]
                  if pkmn_m && pkmn_m.id > 0
                    @battler.moves[i] = PokeBattle_Move.pbFromPBMove(@battle, pkmn_m)
                  else
                    @battler.moves[i] = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(0))
                  end
                end
              end

              # Sincronizar página con los botones
              @buttons.page = @page if @buttons && @buttons.respond_to?(:page=)
              
              if @index == 8
                @window.index = -1 rescue nil
                # Usar movimientos de la página actual para los botones
                page_moves = @battler.moves[(@page * 4), 4] || []
                while page_moves.respond_to?(:length) && page_moves.length < 4
                  page_moves.push(PBMove.new(0))
                end
                
                @buttons.refresh(8, page_moves, @megaButton) if @buttons
                return
              end
              
              # Lógica para índices 0-3 pero con offset de página
              commands = []
              # Re-poblar ventana de comandos con los movimientos de la página actual
              current_moves = @battler.moves[(@page * 4), 4] || []
              # ASEGURAR 4 ELEMENTOS PARA EVITAR CRASH EN FightMenuButtons
              while current_moves.respond_to?(:length) && current_moves.length < 4
                current_moves.push(PBMove.new(0))
              end
              
              for i in 0...4
                break if !current_moves[i] || current_moves[i].id == 0
                commands.push(current_moves[i].name)
              end
              @window.commands = commands
              
              selmove = current_moves[@index]
              if selmove
                movetype = PBTypes.getName(selmove.type)
                if selmove.totalpp == 0
                  @info.text = _ISPRINTF("{1:s}PP: ---<br>TIPO/{2:s}", @ctag, movetype)
                else
                  @info.text = _ISPRINTF("{1:s}PP: {2: 2d}/{3: 2d}<br>TIPO/{4:s}",
                    @ctag, selmove.pp, selmove.totalpp, movetype)
                end
              end
              @buttons.refresh(@index, current_moves, @megaButton) if @buttons
            end
          end

          class FightMenuButtons
            attr_accessor :page
            
            unless method_defined?(:update_orig_eff_hook)
              alias update_orig_eff_hook update
              attr_accessor :hover_index
              attr_accessor :hover_frame
            end
            
            def update(index=0, moves=nil, megaButton=0)
              @hover_index = -1 if !@hover_index
              @hover_frame = 0 if !@hover_frame
              @global_frame = 0 if !@global_frame
              @global_frame += 1
              
              if @hover_index != index
                @hover_index = index
                @hover_frame = 0 # Reiniciar animación al cambiar de botón
              elsif @hover_frame < 12
                @hover_frame += 1 # 12 frames de animación (200ms aprox a 60fps)
              end
              
              update_orig_eff_hook(index, moves, megaButton)
            end

            unless method_defined?(:refresh_orig_eff_hook)
              alias refresh_orig_eff_hook refresh
            end
            def refresh(index, moves, megaButton)
              # SI RECIBIMOS LOS 8 MOVIMIENTOS (desafase detectado), REBAJAMOS A LOS 4 DE LA PÁGINA
              # Guardamos el conteo real antes de recortar para saber si mostrar el botón de página
              real_moves_count = 0
              if moves && moves.respond_to?(:each)
                moves.each { |m| real_moves_count += 1 if m && m.id > 0 }
              end

              if moves && moves.respond_to?(:length) && moves.length > 4
                @page = 0 if !@page
                moves = moves[(@page * 4), 4] || []
                # Rellenar con vacíos si es necesario para evitar crashes en el original
                while moves.length < 4
                  moves.push(PBMove.new(0))
                end
              end
              
              refresh_orig_eff_hook(index, moves, megaButton)
              return if !moves # <-- PROTECCIÓN CRÍTICA
              
              pbSetSmallFont(self.bitmap)
              @page = 0 if !@page # Fallback de seguridad
              
              if real_moves_count > 4
                bx, by = 6, UPPERGAP - 24 # Posición encima del primer botón
                bw, bh = 80, 24
                # --- DIBUJAR RECUADRO ---
                if index == 8 # SI ESTÁ SELECCIONADO: Contorno rojo
                  self.bitmap.fill_rect(bx-2, by-2, bw+4, bh+4, Color.new(255, 0, 0)) # Borde rojo
                  self.bitmap.fill_rect(bx, by, bw, bh, Color.new(0, 0, 0, 180)) # Fondo semi-transparente más oscuro
                else
                  self.bitmap.fill_rect(bx, by, bw, bh, Color.new(0, 0, 0, 150)) # Fondo semi-transparente
                  self.bitmap.fill_rect(bx+1, by+1, bw-2, bh-2, Color.new(255, 255, 255, 50)) # Borde interno
                end

                # --- DIBUJAR TEXTO ---
                btn_text = (@page == 0) ? "MOV 2" : "MOV 1"
                pbDrawTextPositions(self.bitmap, [
                  [btn_text, bx + bw/2, by + 2, 2, Color.new(248, 248, 248), Color.new(32, 32, 32)]
                ])
              end

              old_size = self.bitmap.font.size
              
              # --- LÓGICA DEL CARRUSEL (Sólo Caja de Información Derecha) ---
              @carousel_frame = (@carousel_frame || 0) + 1
              cycle = @carousel_frame % 800 # Ciclo de ~15 segundos (lento)
              @carousel_page = (cycle < 400) ? 0 : 1
              
              # Fundido súper suave (60 frames)
              alpha = 255
              if cycle >= 340 && cycle < 400; alpha = (255 * (1.0 - (cycle-340)/60.0)).to_i
              elsif cycle >= 400 && cycle < 460; alpha = (255 * ((cycle-400)/60.0)).to_i
              elsif cycle >= 740; alpha = (255 * (1.0 - (cycle-740)/60.0)).to_i
              elsif cycle < 60; alpha = (255 * (cycle/60.0)).to_i
              end
              
              mv = moves[index] rescue nil
              if mv && mv.id > 0
                cx = 461 # Centro visual (valor de compromiso)
                ix = 429 # X para los iconos (461 - 32px)
                # Limpiamos exhaustivamente el área
                self.bitmap.clear_rect(390, 20+UPPERGAP, self.bitmap.width-390, 100)
                base_c = Color.new(248, 248, 248, alpha); shad_c = Color.new(32, 32, 32, alpha)
                self.bitmap.font.size = 22 # Fuente óptima para el carrusel
                
                # Nuevas coordenadas para mejor centrado vertical
                y_icon = 22 + UPPERGAP
                y_text = 56 + UPPERGAP
                
                if @carousel_page == 0
                  # Capa 1: Tipo + PP (Alineación 1 = Centro)
                  self.bitmap.blt(ix, y_icon, @typebitmap.bitmap, Rect.new(0, mv.type * 28, 64, 28), alpha)
                  pp_s = (mv.totalpp == 0) ? "PP: ---" : "PP: #{mv.pp}/#{mv.totalpp}"
                  pbDrawTextPositions(self.bitmap, [[pp_s, cx, y_text, 1, base_c, shad_c]])
                else
                  # Capa 2: Categoría + Precisión
                  cat = 2 # Estado por defecto
                  if mv.basedamage > 0
                    cat = 0 # Asumir Físico si tiene daño y falla la detección
                    t = mv.type rescue 0
                    if mv.respond_to?(:pbIsPhysical?); cat = mv.pbIsPhysical?(t) ? 0 : 1
                    elsif mv.respond_to?(:category) && mv.category != nil; cat = mv.category
                    end
                  end
                  
                  acc_s = (mv.accuracy == 0 || mv.accuracy.nil?) ? "---" : "#{mv.accuracy}%"
                  begin
                    catbmp = AnimatedBitmap.new("Graphics/Pictures/category")
                    self.bitmap.blt(ix, y_icon, catbmp.bitmap, Rect.new(0, cat*28, 64, 28), alpha); catbmp.dispose
                  rescue
                    cat_name = ["FISICO", "ESPECIAL", "ESTADO"][cat]
                    pbDrawTextPositions(self.bitmap, [[cat_name, cx, y_icon, 1, base_c, shad_c]])
                  end
                  # Abreviamos Precisión a Prec. y usamos alineación central (1)
                  pbDrawTextPositions(self.bitmap, [[_INTL("Prec: {1}", acc_s), cx, y_text, 1, base_c, shad_c]])
                end
                # RESTAURACIÓN CRÍTICA: Devolvemos la fuente a su estado original para los botones
                self.bitmap.font.size = old_size
              end
              
              # --- LÓGICA DE EFECTIVIDAD (Cálculos de botones) ---
              return if !$_fight_menu_battler || !$_fight_menu_battle
              attacker = $_fight_menu_battler; battle = $_fight_menu_battle
              
              opponents = []
              for i in 0...4
                b = battle.battlers[i]
                opponents.push(b) if b && !b.isFainted? && b.pbIsOpposing?(attacker.index)
              end
              return if opponents.length == 0
          
              for i in 0...4
                move = moves[i]
                next if move.nil? || move.id == 0
          
                x = ((i%2)==0) ? 4 : 192
                y = ((i/2)==0) ? 6 : 48
                y += UPPERGAP
                
                target = move.target
                next if target == PBTargets::User || target == PBTargets::UserSide || 
                        target == PBTargets::Partner || target == PBTargets::UserOrPartner || 
                        target == PBTargets::NoTarget
                        
                best_mod = -1
                worst_mod = 999
                is_leech_seed_immune = false
                
                for opp in opponents
                  real_type = move.pbType(move.type, attacker, opp)
                  mod = move.pbTypeModifier(real_type, attacker, opp)
                  
                  best_mod = mod if mod > best_mod
                  worst_mod = mod if mod < worst_mod
                  
                if move.function == 0xDC && opp.pbHasType?(:GRASS)
                  is_leech_seed_immune = true
                end
              end
              
              has_stab = attacker.pbHasType?(move.type)
              
              str = ""
              curtain_text = ""
              color = Color.new(255,255,255)
              
              if move.pbIsStatus?
                if worst_mod == 0 || is_leech_seed_immune
                  str = "(X)"
                  curtain_text = "INMUNE"
                  color = Color.new(200, 200, 200)
                else
                  next
                end
              else
                if best_mod > 8
                  str = "(+)"
                  curtain_text = "SÚPER EFICAZ"
                  color = Color.new(120, 255, 120) # Verde pastel
                elsif best_mod == 0
                  str = "(X)"
                  curtain_text = "INMUNE"
                  color = Color.new(200, 200, 200) # Gris
                elsif best_mod < 8
                  str = "(-)"
                  curtain_text = "POCO EFICAZ"
                  color = Color.new(255, 150, 150) # Rojo claro
                else
                  # Aunque el ataque sea x1 (neutro), si tiene STAB no hacemos 'next' 
                  # para poder mostrarle el pulso de caja, aunque no tenga texto especial.
                end
              end
        
              # Animación de brillo constante (Glow Web) compartida por ambos estados
              pulse = (Math.sin((@global_frame || 0) / 10.0) + 1.0) / 2.0 # Oscila de 0.0 a 1.0 lentamente
              
              glow_r = color.red + ( (255 - color.red) * (pulse * 0.7) )
              glow_g = color.green + ( (255 - color.green) * (pulse * 0.7) )
              glow_b = color.blue + ( (255 - color.blue) * (pulse * 0.7) )
              
              if i == index
                # Cálculo de frames para la animación "CSS"
                frame = @hover_frame || 12
                progress = frame / 12.0
                # Ease-out quad para un movimiento suave
                ease = 1.0 - (1.0 - progress) * (1.0 - progress)
                
                # 1. Limpiar completamente el área del botón para borrar el texto antiguo
                self.bitmap.clear_rect(x, y, 192, 46)
                
                # 2. Redibujamos la textura base del botón pulsado
                self.bitmap.blt(x, y, @buttonbitmap.bitmap, Rect.new(192, move.type*46, 192, 46))
                
                # 3. Reescribimos el nombre del ataque desplazado hacia ARRIBA animado
                # Si el ataque tiene texto de efectividad (ej. Súper Eficaz), lo desplazamos
                anim_y_name = (curtain_text != "") ? (y + 8 - (10 * ease).to_i) : (y + 8)
                
                self.bitmap.font.size = old_size
                pbDrawTextPositions(self.bitmap, [[_INTL("{1}", move.name), x+96, anim_y_name, 2, 
                   PokeBattle_SceneConstants::MENUBASECOLOR, PokeBattle_SceneConstants::MENUSHADOWCOLOR]])
                   
                # 4. Ponemos el texto de efectividad emergiendo (Fade-in + Slide-up) Y CON BRILLO
                if curtain_text != ""
                  anim_y_eff = y + 26 - (6 * ease).to_i
                  alpha = (255 * ease).to_i
                  
                  eff_col = Color.new(glow_r.to_i, glow_g.to_i, glow_b.to_i, alpha)
                  eff_sha = Color.new(0, 0, 0, alpha)
                  
                  self.bitmap.font.size = 20
                  pbDrawTextPositions(self.bitmap, [[curtain_text, x+96, anim_y_eff, 2, eff_col, eff_sha]])
                end
              else
                # Botones INACTIVOS
                
                # === INDICADOR STAB SÚPER EFICAZ (Daño Devastador) ===
                # Si el ataque tiene STAB *y además* es Súper Eficaz contra al menos un oponente,
                # mezclamos su versión "hover" brillante encima para que la caja entera parezca palpitar.
                if has_stab && best_mod > 8 && !move.pbIsStatus?
                  box_glow_alpha = (140 * pulse).to_i 
                  self.bitmap.blt(x, y, @buttonbitmap.bitmap, Rect.new(192, move.type*46, 192, 46), box_glow_alpha)
                end
                
                # === INDICADOR EFECTIVIDAD (Chapita Oculta) ===
                if str != ""
                  self.bitmap.font.size = 18
                  
                  # Posición ajustada para integrarse sin tocar los bordes (Alineación Derecha = 1)
                  chapa_x = x + 172
                  chapa_y = y + 6 # Lo bajamos ligeramente
                  
                  glow_color = Color.new(glow_r.to_i, glow_g.to_i, glow_b.to_i, 255)
                  
                  pbDrawTextPositions(self.bitmap, [[str, chapa_x, chapa_y, 1, glow_color, Color.new(0, 0, 0, 255)]])
                end
              end
            end
            
            self.bitmap.font.size = old_size # Restaurar
          end
        end
          
          # UI Equipo (PartyScreen) y Tipos
          # Extensión de Trainer para seguimiento independiente
          class PokeBattle_Trainer
            attr_accessor :follower_index
            alias pc_sync_init_trainer initialize
            def initialize(name, trainertype)
              pc_sync_init_trainer(name, trainertype)
              @follower_index = 0
            end
          end

          class PokeBattle_Battle
            unless method_defined?(:pbStartBattleCore_orig_party_hook)
              alias pbStartBattleCore_orig_party_hook pbStartBattleCore
            end
            def pbStartBattleCore(canlose)
              $current_battle_for_ui = self
              ret = pbStartBattleCore_orig_party_hook(canlose)
              $current_battle_for_ui = nil
              return ret
            end
            
            # Sincronización PC: Permitir el cambio si el objeto Pokémon ha cambiado tras usar el PC
            unless method_defined?(:pbCanSwitchLax_pc_hook)
              alias pbCanSwitchLax_pc_hook pbCanSwitchLax?
            end
            def pbCanSwitchLax?(idxPokemon, pkmnidxTo, showMessages)
              if pkmnidxTo >= 0
                party = pbParty(idxPokemon)
                battler = @battlers[idxPokemon]
                if battler && battler.pokemonIndex == pkmnidxTo && party[pkmnidxTo] != battler.pokemon
                  return true
                end
              end
              return pbCanSwitchLax_pc_hook(idxPokemon, pkmnidxTo, showMessages)
            end

            # SINCRONIZACIÓN HIERRO: Si el equipo cambió en el PC, forzamos el cambio al intentar actuar
            unless method_defined?(:pbCommandMenu_pc_hook)
              alias pbCommandMenu_pc_hook pbCommandMenu
            end
            def pbCommandMenu(i)
              idx = @battlers[i].pokemonIndex
              if idx >= 0 && pbParty(i)[idx] != @battlers[i].pokemon
                # ¡Desincronización detectada! El Pokémon en el slot que usa este battler es otro.
                # Forzamos que se elija la opción "Pokémon" (2) para que pbSwitchPlayer haga el resto.
                return 2
              end
              return pbCommandMenu_pc_hook(i)
            end

            unless method_defined?(:pbSwitchPlayer_pc_hook)
              alias pbSwitchPlayer_pc_hook pbSwitchPlayer
            end
            def pbSwitchPlayer(index, lax, cancancel)
              idx = @battlers[index].pokemonIndex
              if idx >= 0 && pbParty(index)[idx] != @battlers[index].pokemon
                # Si el Pokémon ha cambiado en el PC, no abrimos la pantalla, 
                # devolvemos el índice directamente para registrar el cambio y gastar turno.
                pbDisplay(_INTL("¡El equipo ha cambiado! {1} sale a combatir.", pbParty(index)[idx].name))
                return idx
              end
              return pbSwitchPlayer_pc_hook(index, lax, cancancel)
            end
          end

          class PokeBattle_Scene
            unless method_defined?(:pbPokemonScreen_pc_hook)
              alias pbPokemonScreen_pc_hook pbPokemonScreen
            end
            unless method_defined?(:pc_sync_follow_pbEndBattle)
              alias pc_sync_follow_pbEndBattle pbEndBattle
            end
            def pbEndBattle(result)
              pc_sync_follow_pbEndBattle(result)
              # Sincronización Overworld: Refrescamos el sprite del Follower al terminar el combate
              if $PokemonTemp && $PokemonTemp.dependentEvents && $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                $PokemonTemp.dependentEvents.refresh_sprite(false)
              end
            end
          end

          class DependentEvents
            def pbGetFollower
              idx = ($Trainer.follower_index || 0)
              return nil if idx == -1
              pkmn = $Trainer.party[idx]
              return (pkmn && !pkmn.isEgg?) ? pkmn : ($Trainer.party[0] || nil)
            end

            unless method_defined?(:pc_sync_refresh_sprite)
              alias pc_sync_refresh_sprite refresh_sprite
            end
            def refresh_sprite(animation=false)
              return if defined?(NO_UPDATE_SWITCH) && $game_switches[NO_UPDATE_SWITCH]
              pkmn = pbGetFollower
              
              if $scene.is_a?(Scene_Map)
                if !pkmn
                  # Ocultar usando opacidad en lugar de nombre nil para evitar TypeError
                  if respond_to?(:pbFollowingOpacity)
                    pbFollowingOpacity(0)
                  elsif $PokemonTemp.dependentEvents.respond_to?(:pbFollowingOpacity)
                     $PokemonTemp.dependentEvents.pbFollowingOpacity(0)
                  end
                elsif !pkmn.isEgg?
                  if respond_to?(:pbFollowingOpacity)
                    pbFollowingOpacity(255)
                  elsif $PokemonTemp.dependentEvents.respond_to?(:pbFollowingOpacity)
                     $PokemonTemp.dependentEvents.pbFollowingOpacity(255)
                  end
                  shiny = pkmn.isShiny?
                  form = pkmn.form > 0 ? pkmn.form : nil
                  shadow = defined?(pkmn.isShadow?) ? pkmn.isShadow? : false
                  change_sprite(pkmn.species, shiny, false, form, pkmn.gender, shadow)
                else
                  if respond_to?(:pbFollowingOpacity)
                    pbFollowingOpacity(255)
                  elsif $PokemonTemp.dependentEvents.respond_to?(:pbFollowingOpacity)
                     $PokemonTemp.dependentEvents.pbFollowingOpacity(255)
                  end
                  setCustomSprite("egg")
                end
              end
              update_stepping
            end
          end

          # Hook global para el grito e interacción
          unless method_defined?(:pc_sync_pbFollowingChat)
            alias pc_sync_pbFollowingChat pbFollowingChat
          end
          def pbFollowingChat
            if $PokemonTemp && $PokemonTemp.dependentEvents
              pkmn = $PokemonTemp.dependentEvents.pbGetFollower
              if pkmn && !pkmn.isEgg?
                pbPlayCry(pkmn.species)
                if pkmn.hp <= 0
                  Kernel.pbMessage(_INTL("{1} está debilitado.\nApenas puede tenerse en pie...", pkmn.name))
                else
                  Kernel.pbMessage(_INTL("Sin duda, tienes el mejor {1} del mundo.", pkmn.name))
                end
                return
              end
            end
            pc_sync_pbFollowingChat
          end

          class PokemonScreen_Scene
            # ... nada de hooks raros aquí, dejamos que PokeBattle_Battle lo gestione
          end

          class PokemonScreen
            unless method_defined?(:pc_sync_follow_pbSwitch)
              alias pc_sync_follow_pbSwitch pbSwitch
            end
            def pbSwitch(oldid, newid)
              pc_sync_follow_pbSwitch(oldid, newid)
              # Mantener el seguimiento si el Pokémon se mueve
              if $Trainer.follower_index == oldid
                $Trainer.follower_index = newid
              elsif $Trainer.follower_index == newid
                $Trainer.follower_index = oldid
              end
              # Refrescar sprite por si acaso
              if $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                $PokemonTemp.dependentEvents.refresh_sprite(false)
              end
            end

            def pbPokemonScreen
              @scene.pbStartScene(@party,@party.length>1 ? _INTL("Elige un Pokémon.") : _INTL("Elige un Pokémon o cancela."),nil)
              loop do
                @scene.pbSetHelpText(@party.length>1 ? _INTL("Elige un Pokémon.") : _INTL("Elige un Pokémon o cancela."))
                pkmnid=@scene.pbChoosePokemon
                break if pkmnid<0
                pkmn=@party[pkmnid]
                commands   = []
                cmdSummary = -1
                cmdDebug   = -1
                cmdExpShare= -1
                cmdFollow  = -1
                cmdMoves   = [-1,-1,-1,-1]
                cmdSwitch  = -1
                cmdName    = -1
                cmdMail    = -1
                cmdItem    = -1
                cmdPokedex = -1          
                cmdRelearn = -1
                
                # Build the commands
                commands[cmdSummary=commands.length]      = _INTL("Datos")
                
                # Opción para seguir (Personalizada para seguimiento independiente)
                if !pkmn.isEgg?
                  if ($Trainer.follower_index || 0) == pkmnid
                    commands[cmdFollow=commands.length]     = _INTL("Meter en la Poké Ball")
                  else
                    commands[cmdFollow=commands.length]     = _INTL("Sacar de la Poké Ball")
                  end
                end
                
                commands[cmdExpShare = commands.length]     = _INTL("Repartir Exp")
                commands[cmdDebug=commands.length]        = _INTL("Depurador") if $DEBUG
                
                for i in 0...pkmn.moves.length
                  move=pkmn.moves[i]
                  if !pkmn.isEgg? && (isConst?(move.id,PBMoves,:MILKDRINK) ||
                                      isConst?(move.id,PBMoves,:SOFTBOILED) ||
                                      HiddenMoveHandlers.hasHandler(move.id))
                    commands[cmdMoves[i]=commands.length] = PBMoves.getName(move.id)
                  end
                end
                
                commands[cmdSwitch=commands.length]       = _INTL("Mover") if @party.length>1
                if !pkmn.isEgg?
                  commands[cmdName=commands.length]       =  _INTL("Mote")
                  if pkmn.mail
                    commands[cmdMail=commands.length]     = _INTL("Carta")
                  else
                    commands[cmdItem=commands.length]     = _INTL("Objeto")
                  end
                end
                commands[cmdPokedex=commands.length]      = _INTL("Pokedex")
                commands[cmdRelearn=commands.length]      = _INTL("Recordar Movimientos")
                commands[commands.length]                 = _INTL("Salir")
                
                command=@scene.pbShowCommands(_INTL("¿Qué hacer con {1}?",pkmn.name),commands)
                havecommand=false
                for i in 0...4
                  if cmdMoves[i]>=0 && command==cmdMoves[i]
                    havecommand=true
                    if isConst?(pkmn.moves[i].id,PBMoves,:SOFTBOILED) ||
                       isConst?(pkmn.moves[i].id,PBMoves,:MILKDRINK)
                      amt=[(pkmn.totalhp/5).floor,1].max
                      if pkmn.hp<=amt
                        pbDisplay(_INTL("No tiene PS suficientes..."))
                        break
                      end
                      @scene.pbSetHelpText(_INTL("¿En cuál Pokémon usarlo?"))
                      oldpkmnid=pkmnid
                      loop do
                        @scene.pbPreSelect(oldpkmnid)
                        pkmnid=@scene.pbChoosePokemon(true,pkmnid)
                        break if pkmnid<0
                        newpkmn=@party[pkmnid]
                        if pkmnid==oldpkmnid
                          pbDisplay(_INTL("¡{1} no puede usar {2} en sí mismo!",pkmn.name,PBMoves.getName(pkmn.moves[i].id)))
                        elsif newpkmn.isEgg?
                          pbDisplay(_INTL("¡{1} no puede usarse en un Huevo!",PBMoves.getName(pkmn.moves[i].id)))
                        elsif newpkmn.hp==0 || newpkmn.hp==newpkmn.totalhp
                          pbDisplay(_INTL("{1} no puede usarse en ese Pokémon.",PBMoves.getName(pkmn.moves[i].id)))
                        else
                          pkmn.hp-=amt
                          hpgain=pbItemRestoreHP(newpkmn,amt)
                          @scene.pbDisplay(_INTL("{1} recuperó {2} puntos de salud.",newpkmn.name,hpgain))
                          pbRefresh
                        end
                        break if pkmn.hp<=amt
                      end
                      break
                    elsif Kernel.pbCanUseHiddenMove?(pkmn,pkmn.moves[i].id)
                      @scene.pbEndScene
                      # UNLOCK SYSTEM: Desbloqueo total para recuperar el control al salir
                      if $game_player
                        $game_player.straighten rescue nil
                        $game_player.force_move_route(RPG::MoveRoute.new) rescue nil
                        $game_player.instance_variable_set(:@move_route_forcing, false) rescue nil
                        $game_player.move_speed = 4 rescue nil
                      end
                      if $game_map && $game_map.respond_to?(:interpreter)
                        interp = $game_map.interpreter
                        interp.instance_variable_set(:@list, nil) rescue nil
                        interp.instance_variable_set(:@index, 0) rescue nil
                        interp.instance_variable_set(:@move_route_waiting, false) rescue nil
                      end
                      if $game_temp 
                        $game_temp.in_menu = false rescue nil
                        $game_temp.menu_calling = false rescue nil
                        $game_temp.common_event_id = 0 rescue nil
                        $game_temp.message_window_showing = false rescue nil
                      end
                      $game_map.need_refresh = true rescue nil if $game_map
                      if $PokemonTemp && $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                        $PokemonTemp.dependentEvents.refresh_sprite rescue nil 
                      end
                      if isConst?(pkmn.moves[i].id,PBMoves,:FLY)
                        scene=PokemonRegionMapScene.new(-1,false)
                        screen=PokemonRegionMap.new(scene)
                        ret=screen.pbStartFlyScreen
                        if ret
                          $PokemonTemp.flydata=ret
                          return [pkmn,pkmn.moves[i].id]
                        end
                        @scene.pbStartScene(@party,
                           @party.length>1 ? _INTL("Elige un Pokémon.") : _INTL("Elige un Pokémon o cancela."))
                        break
                      end
                      return [pkmn,pkmn.moves[i].id]
                    else
                      break
                    end
                  end
                end
                next if havecommand
                
                if cmdSummary>=0 && command==cmdSummary
                  @scene.pbSummary(pkmnid)
                elsif cmdFollow>=0 && command==cmdFollow
                  # Establecer como follower independiente
                  if ($Trainer.follower_index || 0) == pkmnid
                    $Trainer.follower_index = -1 # Ninguno sigue
                    # Forzar refresco para ocultar
                    if $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                      $PokemonTemp.dependentEvents.refresh_sprite(false)
                    end
                    pbDisplay(_INTL("¡Has guardado a {1}!", pkmn.name))
                  else
                    $Trainer.follower_index = pkmnid
                    # Forzar refresco del follower
                    if $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                      $PokemonTemp.dependentEvents.refresh_sprite(false)
                    end
                    pbDisplay(_INTL("¡{1} ahora te sigue!", pkmn.name))
                  end
                elsif cmdDebug>=0 && command==cmdDebug
                  pbPokemonDebug(pkmn,pkmnid)
                  pbRefresh; @scene.pbRefresh rescue nil

                elsif cmdExpShare>=0 && command==cmdExpShare
                  if pkmn.expshare
                    if pbConfirm(_INTL("¿Quieres desactivar el Repartir Experiencia en este Pokémon?"))
                      pkmn.expshare=false
                    end
                  else
                    if pbConfirm(_INTL("¿Quieres activar el Repartir Experiencia en este Pokémon?"))
                      pkmn.expshare=true
                    end
                  end
                elsif cmdSwitch>=0 && command==cmdSwitch
                  @scene.pbSetHelpText(_INTL("¿A qué posición mover?"))
                  oldpkmnid=pkmnid
                  pkmnid=@scene.pbChoosePokemon(true)
                  if pkmnid>=0 && pkmnid!=oldpkmnid
                    pbSwitch(oldpkmnid,pkmnid)
                  end
                elsif cmdName>=0 && command==cmdName
                  speciesname=PBSpecies.getName(pkmn.species)
                  oldname = (pkmn.name && pkmn.name!=speciesname) ? pkmn.name : ""
                  newname = pbEnterPokemonName(_INTL("Mote de {1}"), 0, 10, oldname, pkmn)
                  pkmn.name = (newname=="") ? speciesname : newname
                  pbRefresh
                elsif cmdItem>=0 && command==cmdItem
                  item=pbItemMenu(pkmnid)
                elsif cmdPokedex>=0 && command==cmdPokedex
                  $Trainer.pokedex=true
                  scene=PokemonPokedexScene.new
                  screen=PokemonPokedex.new(scene)
                  screen.pbDexEntry(pkmn.species)
                elsif cmdRelearn>=0 && command==cmdRelearn
                  pbRelearnMoveScreen(pkmn)
                end
              end
              @scene.pbEndScene
              # UNLOCK SYSTEM: Desbloqueo total para recuperar el control al salir
              if $game_player
                $game_player.straighten rescue nil
                $game_player.force_move_route(RPG::MoveRoute.new) rescue nil
                $game_player.instance_variable_set(:@move_route_forcing, false) rescue nil
                $game_player.move_speed = 4 rescue nil
              end
              if $game_map && $game_map.respond_to?(:interpreter)
                interp = $game_map.interpreter
                interp.instance_variable_set(:@list, nil) rescue nil
                interp.instance_variable_set(:@index, 0) rescue nil
                interp.instance_variable_set(:@move_route_waiting, false) rescue nil
              end
              if $game_temp 
                $game_temp.in_menu = false rescue nil
                $game_temp.menu_calling = false rescue nil
                $game_temp.common_event_id = 0 rescue nil
                $game_temp.message_window_showing = false rescue nil
              end
              $game_map.need_refresh = true rescue nil if $game_map
              if $PokemonTemp && $PokemonTemp.dependentEvents.respond_to?(:refresh_sprite)
                $PokemonTemp.dependentEvents.refresh_sprite rescue nil 
              end
              return nil
            end

          end
          
          class PokeSelectionSprite
            unless method_defined?(:refresh_orig_party_hook)
              alias refresh_orig_party_hook refresh
              alias update_orig_party_anim_hook update
              alias dispose_orig_party_anim_hook dispose
            end
            
            def update
              update_orig_party_anim_hook
              return if !@pokemon || @pokemon.isEgg? || !self.bitmap || self.bitmap.disposed?
              
              if @name_sprite && !@name_sprite.disposed?
                @anim_frame = 0 if !@anim_frame
                @anim_frame += 1
                
                # Ciclo de 240 frames (aprox 6 seg a 40fps)
                cycle = @anim_frame % 240
                
                # Crossfade (Nombre vs Tipos Oficiales)
                if cycle < 100
                  @name_sprite.opacity += 15 if @name_sprite.opacity < 255
                  @type_sprite.opacity -= 15 if @type_sprite.opacity > 0
                elsif cycle >= 120 && cycle < 220
                  @name_sprite.opacity -= 15 if @name_sprite.opacity > 0
                  @type_sprite.opacity += 15 if @type_sprite.opacity < 255
                end
                
                # Glow Panel (Pulso)
                if @has_super_effective
                  pulse_alpha = ((Math.sin(@anim_frame / 10.0) + 1.0) / 2.0 * 150).to_i
                  
                  if !@panel_glow_sprite
                    @panel_glow_sprite = Sprite.new(self.viewport)
                    @panel_glow_sprite.bitmap = Bitmap.new(self.bitmap.width, self.bitmap.height)
                    @panel_glow_sprite.blend_type = 1 # ADD
                    # Hacemos una copia exacta de la caja
                    @panel_glow_sprite.bitmap.blt(0, 0, self.bitmap, Rect.new(0,0,self.bitmap.width,self.bitmap.height))
                  end
                  
                  # Sincronizamos coordenadas por si la caja salta
                  @panel_glow_sprite.x = self.x
                  @panel_glow_sprite.y = self.y
                  @panel_glow_sprite.z = self.z + 1
                  @panel_glow_sprite.opacity = pulse_alpha
                else
                  if @panel_glow_sprite && !@panel_glow_sprite.disposed?
                    @panel_glow_sprite.dispose
                    @panel_glow_sprite = nil
                  end
                end
              end
            end
            
            def dispose
              @name_sprite.dispose if @name_sprite && !@name_sprite.disposed?
              @type_sprite.dispose if @type_sprite && !@type_sprite.disposed?
              @panel_glow_sprite.dispose if @panel_glow_sprite && !@panel_glow_sprite.disposed?
              @name_sprite = nil
              @type_sprite = nil
              @panel_glow_sprite = nil
              dispose_orig_party_anim_hook
            end
            
            def refresh
              # Backup del nombre real para que `refresh` original NO lo dibuje y podamos animarlo nosotros
              old_name = @pokemon ? @pokemon.name : ""
              @pokemon.name = "" if @pokemon && !@pokemon.isEgg?
              
              refresh_orig_party_hook
              
              @pokemon.name = old_name if @pokemon && !@pokemon.isEgg?
              return if !@pokemon || @pokemon.isEgg? || !self.bitmap || self.bitmap.disposed?
              
              # Inicialización de sprites hijos
              if !@name_sprite
                @name_sprite = Sprite.new(self.viewport)
                @type_sprite = Sprite.new(self.viewport)
              end
              @name_sprite.bitmap.dispose if @name_sprite.bitmap
              @type_sprite.bitmap.dispose if @type_sprite.bitmap
              
              @name_sprite.bitmap = Bitmap.new(self.bitmap.width, self.bitmap.height)
              @type_sprite.bitmap = Bitmap.new(self.bitmap.width, self.bitmap.height)
              @name_sprite.x = self.x; @name_sprite.y = self.y; @name_sprite.z = self.z + 2
              @type_sprite.x = self.x; @type_sprite.y = self.y; @type_sprite.z = self.z + 2
              
              @type_sprite.opacity = 0 # Tipos ocultos
              @name_sprite.opacity = 255 # Nombre visible
              
              # DIBUJAR: Nombre
              base = Color.new(248, 248, 248)
              shadow = Color.new(80, 80, 80)
              @name_sprite.bitmap.font.name = self.bitmap.font.name rescue "Arial"
              if @name_sprite.bitmap.font.name != "Arial"
                @name_sprite.bitmap.font.size = self.bitmap.font.size rescue 24
              end
              pbDrawTextPositions(@name_sprite.bitmap, [[old_name, 96, 14, 0, base, shadow]])
              
              # DIBUJAR: Imágenes de Tipos
              begin
                typebitmap = AnimatedBitmap.new("Graphics/Pictures/types")
                type1rect = Rect.new(0, @pokemon.type1 * 28, 64, 28)
                
                # Movemos 14 píxeles a la izquierda (de 96 a 82) para no pisar el símbolo masculino/femenino
                @type_sprite.bitmap.blt(82, 16, typebitmap.bitmap, type1rect)
                
                if @pokemon.type1 != @pokemon.type2
                  type2rect = Rect.new(0, @pokemon.type2 * 28, 64, 28)
                  @type_sprite.bitmap.blt(82 + 66, 16, typebitmap.bitmap, type2rect)
                end
              rescue
                # Fallback si no existe la imagen de tipos
                fallback_txt = PBTypes.getName(@pokemon.type1) rescue ""
                pbDrawTextPositions(@type_sprite.bitmap, [[fallback_txt, 96, 14, 0, base, shadow]])
              end
              
              # ANALIZAR: Súper Eficaz en combate activo
              @has_super_effective = false
              if $current_battle_for_ui && $current_battle_for_ui.battlers
                battle = $current_battle_for_ui
                opponents = []
                for i in [1, 3] # Enemigos
                  b = battle.battlers[i]
                  opponents.push(b) if b && !b.isFainted?
                end
                
                if opponents.length > 0
                  dummy_attacker = PokeBattle_Battler.new(battle, 0)
                  dummy_attacker.pbInitDummyPokemon(@pokemon, 0)
                  
                  for pb_move in @pokemon.moves
                    next if pb_move.nil? || pb_move.id == 0
                    dummy_move = PokeBattle_Move.pbFromPBMove(battle, pb_move)
                    next if dummy_move.nil? || dummy_move.pbIsStatus? || dummy_move.type < 0
                    
                    target = dummy_move.target
                    next if target == PBTargets::User || target == PBTargets::UserSide || 
                            target == PBTargets::Partner || target == PBTargets::UserOrPartner || 
                            target == PBTargets::NoTarget
                            
                    for opp in opponents
                      real_type = dummy_move.pbType(dummy_move.type, dummy_attacker, opp)
                      mod = dummy_move.pbTypeModifier(real_type, dummy_attacker, opp)
                      if mod > 8
                        @has_super_effective = true
                        break
                      end
                    end
                    break if @has_super_effective
                  end
                end
              end
              
              # Reprocesar el GLOW si ya existía para copiar la caja fresca (HPs nuevos, etc)
              if @has_super_effective && @panel_glow_sprite && @panel_glow_sprite.bitmap
                @panel_glow_sprite.bitmap.clear
                @panel_glow_sprite.bitmap.blt(0, 0, self.bitmap, Rect.new(0,0,self.bitmap.width,self.bitmap.height))
              end
            end
          end
        CODE
      end

      # --- Descripción del objeto en TODAS las pestañas del Resumen ---
      # Interceptamos pbShowSummary en Kernel: se llama cuando el jugador abre "Datos"
      if !@summary_item_desc_hook && Kernel.respond_to?(:pbShowSummary, true)
        @summary_item_desc_hook = true
        begin
          Kernel.module_eval do
            class << self
              unless method_defined?(:pbShowSummary_item_desc_orig)
                alias pbShowSummary_item_desc_orig pbShowSummary
              end
            end

            def self.pbShowSummary(party, partyindex, *args)
              # Crear viewport propio encima de todo
              begin
                _vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
                _vp.z = 99990
                _sp = Sprite.new(_vp)
                _sp.bitmap = Bitmap.new(254, 54)
                _sp.x = 258
                _sp.y = 328
                _sp.z = 1

                def _sp.draw_item(pkmn)
                  return if !pkmn || !self.bitmap || self.bitmap.disposed?
                  bmp = self.bitmap
                  bmp.clear
                  begin
                    item = pkmn.item rescue 0
                    if item && item > 0
                      iname = PBItems.getName(item) rescue "???"
                      idesc = pbGetMessage(MessageTypes::ItemDescriptions, item) rescue ""
                      idesc = idesc.to_s.gsub(/\r?\n/, " ").strip
                    else
                      iname = nil; idesc = ""
                    end
                    bmp.fill_rect(0, 0, 254, 54, Color.new(0, 0, 0, 155))
                    bmp.fill_rect(0,  0, 254, 2, Color.new(255, 215, 0, 230))
                    bmp.fill_rect(0, 52, 254, 2, Color.new(255, 215, 0, 230))
                    gold  = Color.new(255, 215, 0); dgold = Color.new(80, 60, 0)
                    white = Color.new(220, 220, 220); shad = Color.new(40, 40, 40)
                    old_sz = bmp.font.size; bmp.font.size = 16
                    if iname
                      pbDrawTextPositions(bmp, [["OBJ: #{iname}", 5, 3, 0, gold, dgold]])
                      dsht = idesc.length > 50 ? idesc[0,50]+"…" : idesc
                      pbDrawTextPositions(bmp, [[dsht, 5, 22, 0, white, shad]]) if idesc != ""
                    else
                      pbDrawTextPositions(bmp, [["Sin objeto equipado", 5, 18, 0, white, shad]])
                    end
                    bmp.font.size = old_sz
                  rescue
                  end
                end

                # Dibujo inicial
                _sp.draw_item(party[partyindex]) rescue nil
              rescue
                _vp = nil; _sp = nil
              end

              # Llamar al original (bloquea hasta que se cierre el Resumen)
              ret = Kernel.pbShowSummary_item_desc_orig(party, partyindex, *args)

              # Limpiar overlay
              begin; _sp.dispose rescue nil; _vp.dispose rescue nil; rescue; end
              return ret
            end
          end
        rescue
        end
      end

    rescue => e
          # Error silencioso
        end
      end

      # Tracing de Pokemon Debug
      if defined?(PokemonScreen) && !@trace_init
        @trace_init = true
        Object.class_eval <<-'CODE'
          Object.const_get(:PokemonScreen).class_eval {
            unless method_defined?(:pbPokemonDebug_F)
              alias pbPokemonDebug_F pbPokemonDebug
              def pbPokemonDebug(pkmn, pkmnid)
                $_debug_pkmn = pkmn
                $last_debug_pkmn_final = pkmn
                pbPokemonDebug_F(pkmn, pkmnid)
                $_debug_pkmn = nil
              end
            end
          } rescue nil
          Object.const_get(:PokemonStorageScreen).class_eval {
            unless method_defined?(:debugMenu_F)
              alias debugMenu_F debugMenu
              def debugMenu(s, p, h)
                $_debug_pkmn = p
                $last_debug_pkmn_final = p
                debugMenu_F(s, p, h)
                $_debug_pkmn = nil
              end
            end
          } rescue nil
          
          # Intercepción del comando "Habilidad" en la UI (pbShowCommands)
          classes_to_hook = []
          begin; classes_to_hook << Object.const_get(:PokemonScreen_Scene); rescue; end
          begin; classes_to_hook << Object.const_get(:PokemonStorageScene); rescue; end
          
          classes_to_hook.compact.each do |klass|
            klass.class_eval {
              unless method_defined?(:pbShowCommands_orig_abil_hook)
                alias pbShowCommands_orig_abil_hook pbShowCommands
              end
              
              def pbShowCommands(helptext, commands, index=0)
                txt = helptext.to_s.downcase
                norm = txt.tr("áéíóúüñ", "aeiouun") rescue txt
                

                # Detectar el menú principal del Depurador de Pokémon (¿qué hacer con X?)
                # Verificamos que tenga la opción "Pokérus" o "Huevo" para garantizar que NO es el menú estándar del equipo.
                if norm.include?("hacer con") && commands.is_a?(Array) && commands.last && commands.last.to_s.downcase.include?("salir") && !$current_battle_for_ui && $DEBUG
                  is_debug_menu = commands.any? { |c| c.to_s.downcase.tr("áéíóúüñ", "aeiouun").include?("pokerus") || c.to_s.downcase.tr("áéíóúüñ", "aeiouun").include?("huevo") || c.to_s.downcase.tr("áéíóúüñ", "aeiouun").include?("duplicar") }
                  
                  if is_debug_menu
                    new_commands = commands.clone
                    idx_salir = new_commands.length - 1
                    new_commands.insert(idx_salir, "Estadísticas")
                    new_commands.insert(idx_salir + 1, "Tipos Custom")
                    new_commands.insert(idx_salir + 2, "Dar Objeto")
                    
                    res = pbShowCommands_orig_abil_hook(helptext, new_commands, index)
                    if res < idx_salir && res != -1
                      return res
                    elsif res == idx_salir
                      pkmn = $_debug_pkmn || $last_debug_pkmn_final
                      if pkmn
                        Kernel.pbChooseStatsMenu_FINAL(pkmn)
                      end
                      return 99 # ID ficticio para que el loop original rebote
                    elsif res == idx_salir + 1
                      pkmn = $_debug_pkmn || $last_debug_pkmn_final
                      if pkmn
                        Kernel.pbChooseTypeMenu_FINAL(pkmn)
                      end
                      return 99 # ID ficticio para que el loop original rebote
                    elsif res == idx_salir + 2
                      pkmn = $_debug_pkmn || $last_debug_pkmn_final
                      if pkmn
                        Kernel.pbChooseItemAdvanced_FINAL(pkmn, nil)
                      end
                      return 99 # ID ficticio para que el loop original rebote
                    elsif res > idx_salir + 2
                      return res - 3
                    else
                      return res
                    end
                  end
                end

                # Detectar menú de habilidades buscando "habilidad" en el texto de ayuda
                # y "Quitar modificaci" o "Quitar cambio" en el último comando.
                last_cmd = commands.last.to_s.downcase.tr("áéíóúüñ", "aeiouun") rescue ""
                if norm.include?("habilidad") && commands.is_a?(Array) && (last_cmd.include?("quitar modificaci") || last_cmd.include?("quitar cambio"))
                  pkmn = $_debug_pkmn || $last_debug_pkmn_final
                  if pkmn
                    ab_id = Kernel.pbChooseAbilitySelection_FINAL(pkmn)
                    if ab_id != nil
                      if ab_id == 0 # Resetear a natural
                        pkmn.abilityflag = nil
                      else
                        # setAbility toma el ID de la habilidad gracias al truco de @abilityflag > 10
                        # Aunque los ID sean menores a 10, usaremos un truco estableciendo directamente la variable
                        pkmn.instance_variable_set(:@abilityflag, ab_id)
                      end
                    end
                    # Retornamos -1 para que el menú original "cancele" y no procese comandos erroneos
                    return -1
                  end
                elsif norm.include?("naturaleza") && commands.is_a?(Array) && (last_cmd.include?("quitar modificaci") || last_cmd.include?("quitar cambio"))
                  pkmn = $_debug_pkmn || $last_debug_pkmn_final
                  if pkmn
                    nat_id = Kernel.pbChooseNatureSelection_FINAL(pkmn)
                    if nat_id != nil
                      if nat_id == -99 # Reset
                        pkmn.natureflag = nil
                      else
                        pkmn.setNature(nat_id)
                        pkmn.calcStats
                      end
                    end
                    return -1
                  end
                end
                return pbShowCommands_orig_abil_hook(helptext, commands, index)
              end
            }
          end
        CODE
      end

      # Teclas rápidas
      @ak ||= (Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i') rescue nil)
      if @ak
        c = ([0xBF, 0xBA, 0xDC].any?{|k| @ak.call(k) & 0x8000 != 0 })
        if c && !@cp; $DEBUG = !$DEBUG; Audio.se_play("Audio/SE/Choose",80,100) rescue nil; end
        @cp = c
        # (Deshabilitado temporalmente) f = @ak.call(0x72) & 0x8000 != 0
        # if f && !@f3p; $mega_shiny_toggle = !$mega_shiny_toggle; Audio.se_play("Audio/SE/Choose",80,100) rescue nil; end
        # @f3p = f
      end
      # --- Overlay de Objeto para PokemonSummaryScene ---
      if !Kernel.respond_to?(:_summary_item_hook_2026)
        Kernel.module_eval { def self._summary_item_hook_2026; end }
        
        # En Essentials la escena de gráficos es normalmente PokemonSummaryScene (o PokemonSummary_Scene)
        # y la lógica es PokemonSummary. El txt dice que existe PokemonSummaryScene.
        begin
          PokemonSummaryScene.class_eval do
            
            # 1. Crear el sprite al entrar a la escena
            unless method_defined?(:pbStartScene_item_hook)
              alias pbStartScene_item_hook pbStartScene
              def pbStartScene(*args, &block)
                res = pbStartScene_item_hook(*args, &block)
                begin
                  # Viewport para todo
                  vp = (@viewport || @sprites.values.first.viewport) rescue Viewport.new(0,0,512,384)
                  @_itm_box_vp = vp # Para no crear viewport extra en vano
                  
                  # Coordenadas generales del cuadro (un poco más a la izquierda: x=230)
                  # Tamaño vuelve al original: 246x42
                  # Coordenadas generales del cuadro
                  box_x = 230
                  box_y = 8
                  
                  # 1) Sprite base: Caja y Título (Ahora 64px de alto para 2 líneas)
                  @_itm_overlay = Sprite.new(vp)
                  @_itm_overlay.z = 99999
                  @_itm_overlay.bitmap = Bitmap.new(246, 64)
                  @_itm_overlay.x = box_x
                  @_itm_overlay.y = box_y - 8 # para animación de fade/slide
                  @_itm_overlay.opacity = 0
                  
                  # 2) Sprite texto: Descripción con marquesina (un poco más alta para 2 líneas si hace falta)
                  @_itm_marquee = Sprite.new(vp)
                  @_itm_marquee.z = 99999 + 1
                  @_itm_marquee.bitmap = Bitmap.new(1200, 44) # Bitmap gigante
                  @_itm_marquee.x = box_x + 5
                  @_itm_marquee.y = box_y - 8 + 20 # misma animación en Y
                  @_itm_marquee.opacity = 0
                  @_itm_marquee.src_rect = Rect.new(0, 0, 236, 44) # Solo "ventana" de visión
                  
                  @_itm_last_pkmn = nil
                  @_itm_marquee_x = 0
                  @_itm_txt_w = 0
                  @_itm_pause_frames = 60 
                  @_itm_in_subview = false # Flag para esconder en EV/IV
                rescue
                end
                res
              end
            end
            
            # 2. Destruirlo al salir
            unless method_defined?(:pbEndScene_item_hook)
              alias pbEndScene_item_hook pbEndScene
              def pbEndScene(*args, &block)
                begin
                  if @_itm_overlay
                    @_itm_overlay.bitmap.dispose rescue nil
                    @_itm_overlay.dispose rescue nil
                  end
                  if @_itm_marquee
                    @_itm_marquee.bitmap.dispose rescue nil
                    @_itm_marquee.dispose rescue nil
                  end
                rescue; end
                pbEndScene_item_hook(*args, &block)
              end
            end
            
            # 3. Mantenerlo actualizado
            # Hook para Habilidades (sub-vista de información)
            unless method_defined?(:_itm_old_habilidades)
              alias _itm_old_habilidades Habilidades
              def Habilidades(pokemon)
                @_itm_in_habilidades = true
                _itm_old_habilidades(pokemon)
                @_itm_in_habilidades = false
              end
            end

            def _update_itm_overlay
              return if !@_itm_overlay || @_itm_overlay.disposed?
              
            # Resetear estado si cambiamos de página o de Pokémon
            pkmn = @pokemon rescue nil
            if (pkmn && pkmn != @_itm_last_pkmn)
              @_itm_in_subview = false
            end

            # Lógica de visibilidad (Esconder si estamos en la sub-vista de Habilidades)
            target_opacity = (@_itm_in_habilidades || @_itm_in_subview) ? 0 : 255
            if @_itm_overlay.opacity != target_opacity
              step = 50 # Animación más rápida
              if @_itm_overlay.opacity < target_opacity
                @_itm_overlay.opacity += step
                # Animación de deslizamiento hacia abajo al aparecer
                if @_itm_overlay.y < 8
                  @_itm_overlay.y += 2
                end
              else
                @_itm_overlay.opacity -= step
                # Animación de deslizamiento hacia arriba al desaparecer
                if @_itm_overlay.y > 0
                  @_itm_overlay.y -= 2
                end
              end
              @_itm_overlay.opacity = target_opacity if (@_itm_overlay.opacity - target_opacity).abs < step
              @_itm_marquee.opacity = @_itm_overlay.opacity if @_itm_marquee
              @_itm_marquee.y = @_itm_overlay.y + 20 if @_itm_marquee
            end

              # Marquesina del texto (Solo si el texto es muy largo)
              if @_itm_marquee && @_itm_txt_w > 236
                if @_itm_pause_frames > 0
                  @_itm_pause_frames -= 1
                else
                  @_itm_marquee_x += 1
                  if @_itm_marquee_x > (@_itm_txt_w - 236 + 20)
                    @_itm_marquee_x = 0
                    @_itm_pause_frames = 90
                  elsif @_itm_marquee_x == (@_itm_txt_w - 236 + 10)
                    @_itm_pause_frames = 60
                  end
                  @_itm_marquee.src_rect.x = @_itm_marquee_x
                end
              end

              pkmn = nil
              begin
                pkmn = @pokemon if defined?(@pokemon)
                if !pkmn && defined?(@party) && defined?(@partyindex)
                  pkmn = @party[@partyindex] if @party && @partyindex
                end
              rescue; end
              
              if pkmn && pkmn != @_itm_last_pkmn
                @_itm_last_pkmn = pkmn
                
                # Reiniciar animación
                @_itm_overlay.opacity = 0
                @_itm_overlay.y = 0
                @_itm_marquee.opacity = 0
                @_itm_marquee.y = 20
                @_itm_marquee_x = 0
                @_itm_pause_frames = 60
                @_itm_marquee.src_rect.x = 0 if @_itm_marquee
                
                bmp = @_itm_overlay.bitmap
                bmp.clear
                bmp_m = @_itm_marquee.bitmap
                bmp_m.clear
                
                begin
                  item = pkmn.item rescue 0
                  if item && item > 0
                    iname = PBItems.getName(item) rescue "Objeto"
                    idesc = (pbGetMessage(MessageTypes::ItemDescriptions, item) rescue "").to_s.gsub(/\r?\n/," ").strip
                  else
                    iname = nil; idesc = ""
                  end
                  
                  # Dibujar caja de 64px de alto
                  bw = 246; bh = 64
                  bmp.fill_rect(0, 0, bw, bh, Color.new(0, 0, 0, 165))
                  bmp.fill_rect(0, 0, bw, 2, Color.new(255, 215, 0, 230))
                  bmp.fill_rect(0, bh - 2, bw, 2, Color.new(255, 215, 0, 230))
                  gold = Color.new(255, 215, 0); dgold = Color.new(80, 60, 0)
                  white = Color.new(240, 240, 240); shad = Color.new(40, 40, 40)
                  
                  bmp.font.size = 15
                  bmp_m.font.size = 15
                  
                  if iname
                    pbDrawTextPositions(bmp, [["OBJ: #{iname}", 5, 2, 0, gold, dgold]])
                    
                    # Word Wrap para 2 líneas
                    words = idesc.split(" ")
                    lines = ["", ""]
                    l_idx = 0
                    words.each do |w|
                      test_line = lines[l_idx] + (lines[l_idx].empty? ? "" : " ") + w
                      # Medimos si cabe en la ventana de 236px
                      if bmp_m.text_size(test_line).width > 230
                        if l_idx == 0
                          l_idx = 1
                          lines[l_idx] = w
                        else
                          # Ya estamos en la segunda línea, acumulamos para el scroll si hace falta
                          lines[l_idx] += " " + w
                        end
                      else
                        lines[l_idx] = test_line
                      end
                    end
                    
                    # Dibujar línea 1 directamente en bmp_m (o bmp)
                    # Si la linea 2 es muy larga, el scroll afectará a ambas (marquesina clásica)
                    # O podemos dibujar la 1 fija y scrollar solo la 2.
                    # El usuario quiere "dos lineas", vamos a poner 2 lineas.
                    # Si el total es muy largo, scrollamos el sprite de texto completo.
                    
                    pbDrawTextPositions(bmp_m, [[lines[0], 0, 0, 0, white, shad]])
                    pbDrawTextPositions(bmp_m, [[lines[1], 0, 18, 0, white, shad]])
                    
                    @_itm_txt_w = [bmp_m.text_size(lines[0]).width, bmp_m.text_size(lines[1]).width].max
                  else
                    @_itm_txt_w = 0
                    pbDrawTextPositions(bmp, [["Sin objeto equipado", 5, 12, 0, white, shad]])
                  end
                rescue; end
              end
            end

            # Dependiendo de la versión, el bucle llama update o pbUpdate
            if method_defined?(:update) && !method_defined?(:update_itm_hook)
              alias update_itm_hook update
              def update(*args, &block)
                update_itm_hook(*args, &block)
                _update_itm_overlay()
              end
            end
            
            if method_defined?(:pbUpdate) && !method_defined?(:pbUpdate_itm_hook)
              alias pbUpdate_itm_hook pbUpdate
              def pbUpdate(*args, &block)
                pbUpdate_itm_hook(*args, &block)
                _update_itm_overlay()
              end
            end
          end
        rescue; end
      end
    end
  end
end

# ===============================================================================
# BOTÓN DE PC EN PANTALLA DE EQUIPO (LATE-BINDING PATCH)
# ===============================================================================


# Hook en Input.update para inyectar el código una vez cargados los scripts
if !defined?($PC_Button_Injector_Hooked)
  $PC_Button_Injector_Hooked = true
  Input.class_eval do
    class << self
      alias _pc_injector_update update rescue nil
      def update
        _pc_injector_update if respond_to?(:_pc_injector_update)
        if !@pc_patch_applied && defined?(PokemonScreen_Scene) && PokemonScreen_Scene.method_defined?(:pbStartScene)
          @pc_patch_applied = true
          
          # Evaluar dinámicamente para evitar SyntaxError (class en método)
          eval <<-'RUBY_CODE'
            class ::PokeSelectionPCSprite < ::PokeSelectionConfirmCancelSprite
              def initialize(viewport=nil, x=270, y=328)
                super("PKM's", x, y, false, viewport)
              end
            end

            class ::PokemonScreen_Scene
              def pbRefresh
                @party = $Trainer.party
                (0...6).each do |i|
                  pkmn = @party[i]
                  sprite = @sprites["pokemon#{i}"]
                  if pkmn
                    if !sprite.is_a?(PokeSelectionSprite)
                      sprite.dispose if sprite
                      @sprites["pokemon#{i}"] = PokeSelectionSprite.new(pkmn, i, @viewport)
                    else
                      sprite.pokemon = pkmn
                    end
                  else
                    if !sprite.is_a?(PokeSelectionPlaceholderSprite)
                      sprite.dispose if sprite
                      @sprites["pokemon#{i}"] = PokeSelectionPlaceholderSprite.new(nil, i, @viewport)
                    else
                      # Placeholder simple
                    end
                  end
                end
              end

              def pbSetHelpText(helptext)
                if @sprites["helpwindow"]
                  @sprites["helpwindow"].text = helptext
                  @sprites["helpwindow"].width = 260
                  @sprites["helpwindow"].visible = true
                end
              end

              def pbStartScene(party, starthelptext, annotations=nil, multiselect=false)
                @sprites = {}
                @party = party
                @viewport = ::Viewport.new(0, 0, ::Graphics.width, ::Graphics.height)
                @viewport.z = 99999
                @multiselect = multiselect
                addBackgroundPlane(@sprites, "partybg", "partybg", @viewport)
                @sprites["messagebox"] = ::Window_AdvancedTextPokemon.new("")
                @sprites["helpwindow"] = ::Window_UnformattedTextPokemon.new(starthelptext)
                @sprites["messagebox"].viewport = @viewport
                @sprites["messagebox"].visible = false
                @sprites["messagebox"].letterbyletter = true
                @sprites["helpwindow"].viewport = @viewport
                @sprites["helpwindow"].visible = true
                pbBottomLeftLines(@sprites["messagebox"], 2)
                pbBottomLeftLines(@sprites["helpwindow"], 1)
                pbSetHelpText(starthelptext)
                (0...6).each do |i|
                  if @party[i]
                    @sprites["pokemon#{i}"] = PokeSelectionSprite.new(@party[i], i, @viewport)
                  else
                    @sprites["pokemon#{i}"] = PokeSelectionPlaceholderSprite.new(@party[i], i, @viewport)
                  end
                  @sprites["pokemon#{i}"].text = annotations[i] if annotations
                end
                
                # Botón PC (Añadido antes del fade)
                @sprites["pokemon_pc"] = ::PokeSelectionPCSprite.new(@viewport, 280, 328)
                @sprites["pokemon_pc"].selected = false
                @sprites["pokemon_pc"].visible = !multiselect
                
                if @multiselect
                  @sprites["pokemon6"] = PokeSelectionConfirmSprite.new(@viewport)
                  @sprites["pokemon7"] = PokeSelectionCancelSprite2.new(@viewport)
                else
                  @sprites["pokemon6"] = PokeSelectionCancelSprite.new(@viewport)
                  @sprites["pokemon6"].selected = false
                end
                @activecmd = 0
                @sprites["pokemon0"].selected = true
                pbFadeInAndShow(@sprites) { update }
              end

              def pbChangeSelection(key, currentsel)
                res = currentsel
                case key
                when ::Input::LEFT
                  if currentsel == (@multiselect ? 8 : 7)
                    res = @multiselect ? 7 : 6
                  else
                    res -= 1
                  end
                when ::Input::RIGHT
                  if currentsel == (@multiselect ? 7 : 6)
                    res = @multiselect ? 8 : 7
                  else
                    res += 1
                  end
                when ::Input::UP
                  if currentsel == (@multiselect ? 7 : 6)
                    res = 4
                  elsif currentsel == (@multiselect ? 8 : 7)
                    res = 5
                  else
                    res -= 2
                  end
                when ::Input::DOWN
                  if currentsel == 4 || currentsel == 5
                    res = @multiselect ? 7 : 6
                  else
                    res += 2
                  end
                end
                
                # Saltar huecos vacíos
                max_pkmn = ($Trainer.party.length - 1)
                if res >= 0 && res < 6 && res > max_pkmn
                  if key == ::Input::RIGHT || key == ::Input::DOWN
                    res = 6 # Salto al PC
                  elsif key == ::Input::LEFT || key == ::Input::UP
                    res = max_pkmn # Vuelta al último mon
                  end
                end

                # Límites estrictos
                max_idx = @multiselect ? 8 : 7
                res = 0 if res < 0
                res = max_idx if res > max_idx
                return res
              end

              alias _pc_pbChoosePokemon pbChoosePokemon rescue nil
              def pbChoosePokemon(switching=false, initialsel=-1)
                (0...6).each do |idx|
                  present = @sprites["pokemon#{idx}"]
                  present.preselected = (switching && idx==@activecmd) if present
                  present.switching = switching if present
                end
                @activecmd = initialsel if initialsel >= 0
                pbRefresh
                loop do
                  ::Graphics.update; ::Input.update; self.update
                  oldsel = @activecmd
                  key = -1; key = ::Input::DOWN if ::Input.repeat?(::Input::DOWN); key = ::Input::RIGHT if ::Input::repeat?(::Input::RIGHT)
                  key = ::Input::LEFT if ::Input::repeat?(::Input::LEFT); key = ::Input::UP if ::Input::repeat?(::Input::UP)
                  @activecmd = pbChangeSelection(key, @activecmd) if key >= 0
                  if @activecmd != oldsel
                    pbPlayCursorSE()
                    (0...6).each { |idx| @sprites["pokemon#{idx}"].selected = (idx == @activecmd) if @sprites["pokemon#{idx}"] }
                    if @multiselect
                      @sprites["pokemon6"].selected = (@activecmd == 6) if @sprites["pokemon6"]
                      @sprites["pokemon7"].selected = (@activecmd == 7) if @sprites["pokemon7"]
                      @sprites["pokemon8"].selected = (@activecmd == 8) if @sprites["pokemon8"]
                    else
                      @sprites["pokemon_pc"].selected = (@activecmd == 6) if @sprites["pokemon_pc"]
                      @sprites["pokemon6"].selected = (@activecmd == 7) if @sprites["pokemon6"]
                    end
                  end
                  return -1 if ::Input.trigger?(::Input::B)
                  if ::Input.trigger?(::Input::C)
                    pc_idx = @multiselect ? 7 : 6; exit_idx = @multiselect ? 8 : 7
                    if @activecmd == pc_idx
                      pbPlayDecisionSE()
                      pbFadeOutIn(99999) { screen = ::PokemonStorageScreen.new(::PokemonStorageScene.new, $PokemonStorage); screen.pbStartScreen(2) }
                      # UNLOCK SYSTEM: Recuperar control al salir de la caja PC
                      if $game_player
                        $game_player.straighten rescue nil
                        $game_player.force_move_route(::RPG::MoveRoute.new) rescue nil
                        $game_player.instance_variable_set(:@move_route_forcing, false) rescue nil
                      end
                      if $game_map && $game_map.respond_to?(:interpreter)
                        interp = $game_map.interpreter
                        interp.instance_variable_set(:@list, nil) rescue nil
                        interp.instance_variable_set(:@index, 0) rescue nil
                        interp.instance_variable_set(:@move_route_waiting, false) rescue nil
                      end
                      $game_map.need_refresh = true rescue nil if $game_map
                      pbRefresh; next
                    end
                    return -1 if @activecmd == exit_idx
                    pbPlayDecisionSE()
                    return @activecmd if @party[@activecmd]
                  end
                end
              end
            end
          RUBY_CODE
        end
      end
    end
  end
end

def pbScreenCapture; end
$_debug_pkmn = nil
$mega_shiny_toggle = false if $mega_shiny_toggle.nil?

# ==============================================================================
# HOOKS DE MODO PORTABLE v4 - Hilo vigilante (sin depender de alias save_data)
# ==============================================================================

$pkmn_usb_dir = begin
  _usb = File.join(Dir.pwd, "Partidas Guardadas")
  Dir.mkdir(_usb) unless File.directory?(_usb)
  _usb
rescue
  nil
end

begin
  if $pkmn_usb_dir
    # Calcular ruta PC nativa
    $pkmn_pc_dir = if ENV['USERPROFILE'] && File.directory?(File.join(ENV['USERPROFILE'], "Saved Games"))
      File.join(ENV['USERPROFILE'], "Saved Games", "Pokemon Z")
    else
      File.join(ENV['APPDATA'] || Dir.pwd, "Pokemon Z")
    end
    Dir.mkdir($pkmn_pc_dir) rescue nil

    $pkmn_usb_save = File.join($pkmn_usb_dir, "Game.rxdata")
    $pkmn_pc_save  = File.join($pkmn_pc_dir,  "Game.rxdata")

    module System
      def self.data_directory
        $pkmn_pc_dir
      end
    end
    module RTP
      def self.getSaveFolder; $pkmn_pc_dir; end
      def self.getSaveFileName(f); File.join($pkmn_pc_dir, f); end
    end

    # === ARRANQUE: USB siempre es la partida "porta" — se inyecta al PC ===
    # Solo copiamos USB->PC si USB existe (es la fuente portable)
    if File.exist?($pkmn_usb_save)
      File.open($pkmn_pc_save, 'wb') { |w| File.open($pkmn_usb_save, 'rb') { |r| w.write(r.read) } } rescue nil
    end

    # === HILO VIGILANTE: detecta cuando el juego guarda en PC y lo copia al USB ===
    Thread.new do
      begin
        _last_mtime = File.exist?($pkmn_pc_save) ? (File.mtime($pkmn_pc_save) rescue nil) : nil
        loop do
          sleep 2
          next unless File.exist?($pkmn_pc_save)
          _cur = File.mtime($pkmn_pc_save) rescue nil
          next unless _cur
          if _last_mtime.nil? || _cur > _last_mtime
            _last_mtime = _cur
            # PC guardo algo nuevo -> copiar al USB
            File.open($pkmn_usb_save, 'wb') { |w|
              File.open($pkmn_pc_save, 'rb') { |r| w.write(r.read) }
            } rescue nil
          end
        end
      rescue
      end
    end

  end
rescue
end

# Heizo NPC - Integrado directamente
$heizo_maps = [10, 18, 30, 45, 60, 82, 104, 114, 134, 142, 164]
$heizo_last_map = 0
$heizo_spawned = false

module Graphics
  class << self
    alias heizo_upd_final update
    def update
      if Graphics.frame_count % 60 == 0
        spawn_heizo_final
      end
      heizo_upd_final
    end
  end
end

def spawn_heizo_final
  return if !$game_map
  current_map = $game_map.map_id
  
  if current_map != $heizo_last_map
    $heizo_last_map = current_map
    $heizo_spawned = false
  end
  
  return if !$heizo_maps.include?(current_map)
  return if $heizo_spawned
  return if $game_map.events[995]
  
  target = nil
  $game_map.events.each do |id, e|
    begin
      name = e.character_name rescue nil
      if name == "cazadorPetri"
        target = e
        break
      end
    rescue
    end
  end
  
  if target
    x = target.x - 1
    y = target.y
  else
    x, y = 7, 8
  end
  
  begin
    re = RPG::Event.new(x, y)
    re.id = 995
    re.name = "HeizoNPC"
    
    page = RPG::Event::Page.new
    page.graphic.character_name = "cazadorow"
    page.graphic.direction = 2
    page.trigger = 0
    page.list = [RPG::EventCommand.new(0, 0, [])]
    
    re.pages = [page]
    
    ge = Game_Event.new($game_map.map_id, re, $game_map)
    $game_map.events[995] = ge
    ge.refresh
    
    if $scene.is_a?(Scene_Map) && $scene.spriteset
      begin
        vp = $scene.spriteset.instance_variable_get(:@viewport1)
        if vp
          spr = Sprite_Character.new(vp, ge)
          arr = $scene.spriteset.instance_variable_get(:@character_sprites)
          arr.push(spr) if arr
        end
      rescue
      end
    end
    
    $heizo_spawned = true
  rescue
  end
end
