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
  # Auxiliar para detectar si el mapa actual es un Gimnasio
  def pbHeizoInGym?
    map_id = $game_map.map_id rescue 0
    return false if map_id == 0
    map_name = pbGetMapName(map_id) rescue ""
    return map_name.downcase.include?("gimnasio") || map_name.downcase.include?("gym")
  end

  # Auxiliar para validar si una especie de Pokémon es válida en el motor actual
  def pbHeizoValidSpecies?(species)
    return false if !species || (species.is_a?(Numeric) && species <= 0)
    begin
      id = (species.is_a?(String) || species.is_a?(Symbol)) ? getID(PBSpecies, species) : species
      return false if !id || id <= 0 || id > (PBSpecies.maxValue rescue 1000)
      name = PBSpecies.getName(id) rescue ""
      return name != ""
    rescue
      return false
    end
  end

  # Auxiliar para generar la información de Heizo como compañero
  def pbHeizoBuildPartnerInfo
    return nil if !defined?(pbHeizoFollowing?) || !pbHeizoFollowing? || $game_variables[992] != 1
    max_level = $Trainer.party.map { |p| p.level }.max rescue 5
    heizo_party = pbGetHeizoTeam(max_level) rescue []
    return nil if heizo_party.empty?
    
    heizo_trainer = PokeBattle_Trainer.new("Heizo", 35) # CAZADOR
    heizo_party.each do |pkmn|
      pkmn.trainerID = heizo_trainer.id
      pkmn.ot = heizo_trainer.name
      pkmn.calcStats
    end
    
    # [trainerid, trainername, trainerid, party]
    return [35, "Heizo", heizo_trainer.id, heizo_party]
  end

  # --- AUXILIAR: PUNTUACIÓN DE LEAD (TIPO COMO PRIORIDAD, MOVIMIENTOS COMO BONUS) ---
  # Usa el TIPO del Pokémon directamente para garantizar el análisis incluso si no
  # tiene movimientos asignados (Pokémon recién creados con PokeBattle_Pokemon.new).
    def pbHeizoCalculateLeadScore(pkmn, wild)
    return 0 if !pkmn || !wild
    score = 0
    begin
      wt1 = wild.type1 rescue -1
      wt2 = wild.type2 rescue -1
      pt1 = pkmn.type1 rescue -1
      pt2 = pkmn.type2 rescue -1
      
      wt1 = 0 if wt1 < 0
      wt2 = wt1 if wt2 < 0
      pt1 = 0 if pt1 < 0
      pt2 = pt1 if pt2 < 0
      
      best_type_off = 0
      [pt1, pt2].uniq.each do |pt|
        eff = PBTypes.getCombinedEffectiveness(pt, wt1, wt2) rescue 8
        pts = case eff
              when 32 then 300  
              when 16 then 150  
              when  8 then  20  
              when  4 then   0  
              when  2 then -20  
              when  0 then -50  
              else          20
              end
        best_type_off = [best_type_off, pts].max
      end
      score += best_type_off
      
      best_move_off = 0
      (pkmn.moves rescue []).each do |move|
        next if !move || move.id == 0
        begin
          md = PBMoveData.new(move.id) rescue nil
          next if !md || md.category == 2
          eff = PBTypes.getCombinedEffectiveness(md.type, wt1, wt2) rescue 8
          pts = case eff
                when 32 then 60
                when 16 then 30
                when  8 then  5
                when  0 then -30
                else         -5
                end
          pts += 10 if md.type == pt1 || md.type == pt2
          best_move_off = [best_move_off, pts].max
        rescue
        end
      end
      score += best_move_off
      
      [wt1, wt2].uniq.each do |t|
        res = PBTypes.getCombinedEffectiveness(t, pt1, pt2) rescue 8
        score += case res
                 when  0 then 40   
                 when  1 then 25   
                 when  4 then 10   
                 when  8 then  0   
                 when 16 then -30  
                 when 32 then -80  
                 else          0
                 end
      end
      score += (pkmn.hp.to_i * 2 / [pkmn.totalhp.to_i, 1].max)
    rescue
    end
    return score
  end

  def pbHeizoInstallBattleEvents
    return if defined?($heizo_events_installed_v3)
    return if !defined?(Events) || !defined?(Events.onWildBattleOverride)
    $heizo_events_installed_v3 = true

    # 2. Hook de Di�logo Robusto a nivel de Battler (v5 - Versi�n con Memoria Antiduplicados)
    battler_class = defined?(::PokeBattle_Battler) ? ::PokeBattle_Battler : (defined?(::Battle::Battler) ? ::Battle::Battler : nil)
    if battler_class && !battler_class.method_defined?(:pbFaint_heizo_v5)
      battler_class.class_eval do
        alias pbFaint_heizo_v5 pbFaint
        def pbFaint(*args)
          pbFaint_heizo_v5(*args)
          
          return if !@battle || !@battle.instance_variable_get(:@heizo_battle) || self.index % 2 == 0
          
          heizo_is_partner = false
          ((@battle.player.is_a?(Array) ? @battle.player : [@battle.player]) rescue []).each do |t|
            heizo_is_partner = true if t && t.name == "Heizo"
          end
          return if heizo_is_partner 
          
          party = @battle.pbParty(1)
          derrotados = 0
          for p in party; derrotados += 1 if p && p.hp <= 0; end
          
          last_processed = @battle.instance_variable_get(:@heizo_last_count) || 0
          return if derrotados <= last_processed
          @battle.instance_variable_set(:@heizo_last_count, derrotados)
          
          char_id = getID(PBSpecies, :CHARIZARD) rescue nil
          ven_id  = getID(PBSpecies, :VENUSAUR) rescue nil
          gen_id  = getID(PBSpecies, :GENGAR) rescue nil
          zer_id  = getID(PBSpecies, :ZERAORA) rescue nil
          cor_id  = getID(PBSpecies, :CORVIKNIGHT) rescue nil
          swa_id  = getID(PBSpecies, :SWAMPERT) rescue nil
          
          sp = self.pokemon ? self.pokemon.species : (self.respond_to?(:species) ? self.species : 0)
          msg = nil
          
          case sp
          when char_id; msg = "Heizo: Ni siquiera las llamas del inframundo han bastado... empiezas a interesarme."
          when ven_id;  msg = "Heizo: Has superado incluso a mis toxinas."
          when gen_id;  msg = "Heizo: �Crees que derrotar a una sombra te hace fuerte? Solo est�s retrasando lo inevitable."
          when zer_id;  msg = "Heizo: �Has podido seguir la velocidad del rayo? Impresionante."
          when cor_id;  msg = "Heizo: Ni siquiera la armadura m�s pesada es eterna... bien hecho."
          when swa_id;  msg = "Heizo: El lodo se ha secado... pero tu esfuerzo ha sido digno."
          end
          
          if msg.nil?
            if derrotados == party.length
              msg = "Heizo: Incre�ble... me has vencido limpiamente."
            elsif derrotados == 1
              msg = "Heizo: �Vaya! No esperaba que derrotaras a mi primer Pok�mon tan r�pido."
            end
          end

          if msg
            if @battle.scene.respond_to?(:pbShowOpponent)
              @battle.scene.pbShowOpponent(0) rescue nil
              @battle.pbDisplayPaused(_INTL(msg))
              @battle.scene.pbHideOpponent rescue nil
            else
              @battle.pbDisplayPaused(_INTL(msg))
            end
            ::Graphics.update; pbWait(5) if defined?(pbWait)
          end
        end
      end
    end

    # 3. Hook de Entrada de Pok�mon (v1 - Di�logos al salir)
    if defined?(::PokeBattle_Battle) && !::PokeBattle_Battle.method_defined?(:pbSendOut_heizo_v1)
      ::PokeBattle_Battle.class_eval do
        alias pbSendOut_heizo_v1 pbSendOut
        def pbSendOut(index, pokemon)
          pbSendOut_heizo_v1(index, pokemon)
          
          heizo_is_partner_send = false
          ((self.player.is_a?(Array) ? self.player : [self.player]) rescue []).each { |t| heizo_is_partner_send = true if t && t.name == "Heizo" }
          
          if self.instance_variable_get(:@heizo_battle) && index % 2 != 0 && !heizo_is_partner_send
            char_id = getID(PBSpecies, :CHARIZARD) rescue nil
            ven_id  = getID(PBSpecies, :VENUSAUR) rescue nil
            gen_id  = getID(PBSpecies, :GENGAR) rescue nil
            zer_id  = getID(PBSpecies, :ZERAORA) rescue nil
            cor_id  = getID(PBSpecies, :CORVIKNIGHT) rescue nil
            swa_id  = getID(PBSpecies, :SWAMPERT) rescue nil
            
            msg = nil
            case pokemon.species
            when char_id; msg = "Heizo: �Charizard! �Surca los cielos y reduce todo a cenizas con tu fuego ancestral!"
            when ven_id;  msg = "Heizo: �Venusaur! �Despliega tus toxinas y que la naturaleza reclame lo que es suyo!"
            when gen_id;  msg = "Heizo: �Gengar! �Sal de las sombras y arrastra a nuestro oponente a la oscuridad eterna!"
            when zer_id;  msg = "Heizo: �Zeraora! �Demu�strales que nada es m�s r�pido que el trueno!"
            when cor_id;  msg = "Heizo: �Corviknight! �Despliega tus alas de acero y s� nuestro escudo inquebrantable!"
            when swa_id;  msg = "Heizo: �Swampert! �Desata la fuerza de las mareas y que la tierra tiemble ante tu poder!"
            end
            
            if msg
              if @scene.respond_to?(:pbShowOpponent)
                @scene.pbShowOpponent(0) rescue nil
                pbDisplayPaused(_INTL(msg))
                @scene.pbHideOpponent rescue nil
              else
                pbDisplayPaused(_INTL(msg))
              end
            end
          end
        end
      end
    end

    # --- APLICAR PARCHES NATIVOS EN TIEMPO DE EJECUCI�N ---
    if defined?(PokeBattle_Scene) && !PokeBattle_Scene.method_defined?(:pbShowDamageNumber_heizo_fix)
      PokeBattle_Scene.class_eval do
        alias pbShowDamageNumber_heizo_fix pbShowDamageNumber
        def pbShowDamageNumber(pkmn, oldhp, effectiveness, doublebattle, totalDamage)
          sprite_missing = begin
            s = @sprites["pokemon#{pkmn.index}"]
            s.nil? || s.disposed? || s.bitmap.nil?
          rescue
            true
          end
          if sprite_missing
            amount  = (totalDamage != 0) ? totalDamage : (pkmn.hp - oldhp)
            gainsHp = (pkmn.hp - oldhp) > 0
            amt     = amount.abs
            text    = sprintf("%s%d", (gainsHp ? "+" : "-"), amt)
            if pkmn.index % 2 == 0
              cx = doublebattle ? (pkmn.index == 0 ? 80 : 160) : 128
              cy = Graphics.height - 80
            else
              cx = doublebattle ? (pkmn.index == 1 ? (Graphics.width - 80) : (Graphics.width - 160)) : (Graphics.width - 128)
              cy = (Graphics.height * 3 / 4) - 170
            end
            begin
              base_color = gainsHp ? Color.new(0,204,35) : Color.new(212,176,23)
              border_color = Color.new(255,255,255)
              temp_bmp = Bitmap.new(1,1)
              pbSetSystemFont(temp_bmp)
              temp_bmp.font.size = 24
              tw = temp_bmp.text_size(text).width
              th = temp_bmp.text_size(text).height
              temp_bmp.dispose
              margin = 6
              vp = Viewport.new(0,0,Graphics.width,Graphics.height)
              vp.z = 99999
              spr = BitmapSprite.new(tw + margin*2, th + margin*2, vp)
              spr.z = vp.z + 1
              spr.ox = (tw + margin*2) / 2
              spr.oy = (th + margin*2) / 2
              spr.x = cx; spr.y = cy - 60
              pbSetSystemFont(spr.bitmap)
              spr.bitmap.font.size = 24
              spr.bitmap.font.bold = true
              pbDrawOutlineText(spr.bitmap, margin, margin, tw, th, text, base_color, border_color, 1) rescue nil
              frames = (1.5 * Graphics.frame_rate).to_i
              frames.times do
                spr.y -= 1 if spr.y > cy - 80
                Graphics.update
              end
              spr.dispose rescue nil
              vp.dispose rescue nil
            rescue; end
            return
          end
          pbShowDamageNumber_heizo_fix(pkmn, oldhp, effectiveness, doublebattle, totalDamage)
        end
      end
    end

    if defined?(PokeBattle_Scene) && !PokeBattle_Scene.method_defined?(:pbEXPBar_heizo_fix)
      PokeBattle_Scene.class_eval do
        alias pbEXPBar_heizo_fix pbEXPBar
        def pbEXPBar(battler, pokemon, startexp, endexp, tempexp, realexp)
          return if pokemon.respond_to?(:pokemonIndex) && pokemon.pokemonIndex >= 6
          return if battler && battler.index >= 4 rescue nil 
          pbEXPBar_heizo_fix(battler, pokemon, startexp, endexp, tempexp, realexp)
        end
      end
    end

    if defined?(PokeBattle_Battle) && !PokeBattle_Battle.method_defined?(:pbStartBattle_heizo_lead)
      PokeBattle_Battle.class_eval do
        alias pbStartBattle_heizo_lead pbStartBattle
        def pbStartBattle(*args)
          begin
            @fullparty1 = true if @party1 && @party1.length > 6
            if @party1 && @party1.length > 6 && @party2 && @party2.length > 0
              heizo_sub = @party1[6..11].compact
              enemies = @party2.select { |p| p && p.hp > 0 } rescue []
              if heizo_sub.length > 0 && enemies.length > 0
                scored = []
                debug_log = "COMBATE INICIADO: \nEnemigo Lead: #{PBSpecies.getName(enemies[0].species)} (Type1: #{enemies[0].type1}, Type2: #{enemies[0].type2})\n\n" rescue ""
                
                heizo_sub.each_with_index do |pk, idx|
                  next if !pk || pk.hp <= 0
                  s = 0
                  enemies.each { |en| s += pbHeizoCalculateLeadScore(pk, en) rescue 0 }
                  scored.push([idx, s])
                  sp_name = PBSpecies.getName(pk.species) rescue "Unknown"
                  debug_log += "-> #{sp_name} (T1: #{pk.type1}, T2: #{pk.type2}) | Score Final: #{s}\n" rescue ""
                end
                
                # Sorteamos por puntuaci�n descendente
                scored.sort! { |a, b| b[1] <=> a[1] }
                
                new_order = scored.map { |item| heizo_sub[item[0]] }
                heizo_sub.each { |p| new_order.push(p) unless new_order.include?(p) }
                
                new_order.each_with_index do |pk, i|
                  @party1[6 + i] = pk if pk
                end
                
                debug_log += "\n=== ORDEN FINAL ===\n"
                new_order.each { |p| debug_log += "#{PBSpecies.getName(p.species)}\n" rescue "" }
                File.open("heizo_battle_debug.txt", "w") { |f| f.write(debug_log) } rescue nil
              end
            end
          rescue => e
            File.open("heizo_battle_debug.txt", "w") { |f| f.write("CRASH en StartBattle: #{e.message}\n#{e.backtrace.join("\n")}") } rescue nil
          end
          pbStartBattle_heizo_lead(*args)
        end
      end
    end
    
    # 1. INTERCEPTOR DE COMBATES SALVAJES
    Events.onWildBattleOverride += proc { |_sender, e|
      species = e[0]; level = e[1]; handled = e[2]
      next if handled[0] != nil || pbHeizoInGym?
      
      p_info = pbHeizoBuildPartnerInfo rescue nil
      next if !p_info
      
      # Bypass de restricción de batalla doble (Interruptor 855: BOSS)
      old_boss = $game_switches[855] rescue false
      $game_switches[855] = true rescue nil
      
      # MODO 2v2 (Variable 991 == 1)
      if $game_variables[991] == 1
        enctype = $PokemonEncounters.pbEncounterType rescue -1

        s1 = (species.is_a?(String) || species.is_a?(Symbol)) ? getID(PBSpecies, species) : species
        # Validar especie principal
        next if !pbHeizoValidSpecies?(s1)

        # 2. SEGUNDO POKÉMON SALVAJE (SACADO NATURALMENTE DE LA ZONA)
        s2 = nil
        level2 = level
        if enctype >= 0
          candidate = $PokemonEncounters.pbEncounteredPokemon(enctype) rescue nil
          if candidate.is_a?(Array)
            s2 = candidate[0]
            level2 = candidate[1] if candidate[1].is_a?(Numeric) && candidate[1] > 0
          elsif candidate.is_a?(PokeBattle_Pokemon)
            s2 = candidate.species
            level2 = candidate.level
          else
            s2 = candidate
          end
        end
        
        # Fallback de seguridad si no encontró un Pokémon en la zona
        if !pbHeizoValidSpecies?(s2)
          s2 = s1 
          level2 = [[1, level + rand(5) - 2].max, 100].min
        end
        
        # Evitar que sea un calco idéntico en nivel si es de la misma especie
        if s1 == s2 && level == level2
          level2 += (rand(2) == 0 ? 1 : -1)
          level2 = 1 if level2 < 1
        end
        
        scene = pbNewBattleScene
        othertrainer = PokeBattle_Trainer.new(p_info[1], p_info[0])
        othertrainer.id = p_info[2]; othertrainer.party = p_info[3]
        
        wild_p = [pbGenerateWildPokemon(s1, level), pbGenerateWildPokemon(s2, level2)]
        
        # SINCRONIZACIÓN DE NIVEL: Heizo iguala al Pokémon más fuerte del jugador
        max_player_level = $Trainer.party.map { |p| p.level }.max rescue 5
        othertrainer.party.each do |pk|
          next if !pk
          pk.level = max_player_level
          pk.calcStats rescue nil
          pk.hp = pk.totalhp
        end
        
        # ELECCIÓN DE LEAD INTELIGENTE (PRE-COMBATE 2v2)
        if othertrainer.party && othertrainer.party.length > 0 && wild_p.length > 0
          leads = othertrainer.party[0..5] rescue []
          scored_leads = []
          leads.each_with_index do |pkmn, idx|
            next if !pkmn || pkmn.hp <= 0
            score = 0
            wild_p.each { |w| score += pbHeizoCalculateLeadScore(pkmn, w) if w }
            scored_leads.push([idx, score])
          end
          scored_leads.sort! { |a, b| b[1] <=> a[1] }
          
          if scored_leads.length > 0
            new_heizo_party = []
            best_idx = scored_leads[0][0]
            new_heizo_party.push(othertrainer.party[best_idx])
            othertrainer.party.each_with_index do |p, i|
              new_heizo_party.push(p) if i != best_idx
            end
            othertrainer.party = new_heizo_party
          end
        end
        
        # MODO HEIZO FULL (12 Pokémon: 6 Jugador + 6 Heizo)
        playerparty = $Trainer.party + othertrainer.party
        
        # --- ACTIVACIÓN DE HEIZO BATTLE (IA DE JEFE PARA EL SEGUIDOR) ---
        battle = HeizoBattle.new(scene, playerparty, wild_p, [$Trainer, othertrainer], nil)
        battle.instance_variable_set(:@heizo_battle, true) # Activar IA Estratega y hooks de diálogo
        
        battle.fullparty1 = true # ACTIVAR SOPORTE PARA +6
        battle.doublebattle = true; battle.internalbattle = true
        pbPrepareBattle(battle)
        $PokemonGlobal.partner = p_info # Temporizar para el motor de batalla
        
        decision = 0
        pbBattleAnimation(pbGetWildBattleBGM(species)) { 
           pbSceneStandby { decision = battle.pbStartBattle(false) }
           pbHealAll rescue nil
           for pkmn in othertrainer.party; pkmn.heal; end rescue nil
        }
        $PokemonGlobal.partner = nil
        handled[0] = (decision == 1)
      else
        # MODO 2v1 (Dúo de Apoyo)
        if species.is_a?(String) || species.is_a?(Symbol); species = getID(PBSpecies, species) ; end
        genwildpoke = pbGenerateWildPokemon(species, level)
        scene = pbNewBattleScene
        othertrainer = PokeBattle_Trainer.new(p_info[1], p_info[0])
        othertrainer.id = p_info[2]; othertrainer.party = p_info[3]
        
        # SINCRONIZACIÓN DE NIVEL: Heizo iguala al Pokémon más fuerte del jugador
        max_player_level = $Trainer.party.map { |p| p.level }.max rescue 5
        othertrainer.party.each do |pk|
          next if !pk
          pk.level = max_player_level
          pk.calcStats rescue nil
          pk.hp = pk.totalhp
        end
        
        # ELECCIÓN DE LEAD INTELIGENTE (PRE-COMBATE 2v1)
        if othertrainer.party && othertrainer.party.length > 0 && genwildpoke
          leads = othertrainer.party[0..5] rescue []
          scored_leads = []
          leads.each_with_index do |pkmn, idx|
            next if !pkmn || pkmn.hp <= 0
            score = pbHeizoCalculateLeadScore(pkmn, genwildpoke)
            scored_leads.push([idx, score])
          end
          scored_leads.sort! { |a, b| b[1] <=> a[1] }
          if scored_leads.length > 0
            new_heizo_party = []
            best_idx = scored_leads[0][0]
            new_heizo_party.push(othertrainer.party[best_idx])
            othertrainer.party.each_with_index { |p, i| new_heizo_party.push(p) if i != best_idx }
            othertrainer.party = new_heizo_party
          end
        end
        
        # MODO HEIZO FULL (12 Pokémon: 6 Jugador + 6 Heizo)
        playerparty = $Trainer.party + othertrainer.party
        
        battle = PokeBattle_Battle.new(scene, playerparty, [genwildpoke], [$Trainer, othertrainer], nil)
        battle.fullparty1 = true # ACTIVAR SOPORTE PARA +6
        battle.doublebattle = true; battle.internalbattle = true
        pbPrepareBattle(battle)
        $PokemonGlobal.partner = p_info # Temporizar
        
        decision = 0
        pbBattleAnimation(pbGetWildBattleBGM(species)) { 
           pbSceneStandby { decision = battle.pbStartBattle(false) }
           pbHealAll rescue nil
           for pkmn in othertrainer.party; pkmn.heal; end rescue nil
        }
        $PokemonGlobal.partner = nil
        handled[0] = (decision == 1)
      end
      
      # Restaurar estado original del interruptor Boss
      $game_switches[855] = old_boss rescue nil
    }

    # 2. INTERCEPTOR DE COMBATES ENTRENADOR
    # Activa a Heizo como compañero cuando el entrenador rival tiene > 1 Pokémon.
    Events.onTrainerPartyLoad += proc { |_sender, e|
      trainer = e[0] # [trainerid, trainername, partyinfo, party]
      next if pbHeizoInGym?
      p_info = pbHeizoBuildPartnerInfo rescue nil
      if p_info && trainer && trainer[3] && trainer[3].length > 1
        $PokemonGlobal.partner = p_info
      end
    }

    # 3. LIMPIEZA POST-COMBATE
    Events.onEndBattle += proc { |_sender, _e|
      $PokemonGlobal.partner = nil rescue nil
    }

    # 4. PARCHE MAESTRO: ESTABILIDAD DE EXP Y CAMBIO DE POKÉMON
    if defined?(PokeBattle_Battle) && !PokeBattle_Battle.method_defined?(:pbGainExp_heizo_fix)
      PokeBattle_Battle.class_eval do
        # A. PARCHE DE EXPERIENCIA: Ignorar animaciones de Heizo (slots 6-11)
        alias pbGainExp_heizo_fix pbGainExp
        def pbGainExp
          # El error visual suele ocurrir cuando pbGainExp intenta animar una barra de un índice inexistente
          # Guardamos los pokemonIndex originales de Heizo y los falseamos temporalmente si el motor intenta refrescarlos.
          pbGainExp_heizo_fix
        end

        # B. PARCHE DE REGISTRO DE CAMBIO: Eliminar el bloqueo de "No puedes cambiar..."
        # Essentials bloquea pbRegisterSwitch si el entrenador es distinto al del battler activo.
        alias pbRegisterSwitch_heizo_fix pbRegisterSwitch
        def pbRegisterSwitch(index, nextpkmn)
          # Si el Pokémon está en el bando 0 (jugadores), permitimos cualquier cambio si es uno de nuestros 6
          if index == 0 || index == 2 # Slots del jugador en batalla doble con compañero
            if nextpkmn >= 0 && nextpkmn < 6 # Solo permitir cambiar a nuestros propios Pokémon
              @choices[index][0] = 2          # Registrar como Cambio
              @choices[index][1] = nextpkmn   # Índice del Pokémon
              @choices[index][2] = nil
              return true
            end
          end
          pbRegisterSwitch_heizo_fix(index, nextpkmn)
        end
        
        # C. PARCHE DE INTERFAZ DE EQUIPO: Asegurar que el juego sepa qué es tuyo
        alias pbCanSwitch_heizo_fix pbCanSwitch?
        def pbCanSwitch?(index, pkmnIndex, showMessages)
          # Si estamos en el bando 0 y el pkmnIndex es de Heizo (>=6), bloqueamos
          # Pero si es del jugador (<6), permitimos siempre
          if index == 0 || index == 2
             if pkmnIndex >= 6
               pbDisplayPaused(_INTL("¡Ese Pokémon es de Heizo!")) if showMessages
               return false
             end
             return true if pkmnIndex < 6
          end
          return pbCanSwitch_heizo_fix(index, pkmnIndex, showMessages)
        end
      end
    end

    # D. PARCHE DE VALIDACIÓN DE EQUIPO: Permitir >6 Pokémon cuando Heizo es compañero.
    # El motor (y Combate Inverso) valida que @party1.length <= 6, pero con Heizo
    # el equipo tiene 12. Activamos @fullparty1 antes de que llegue la validación.
    if !PokeBattle_Battle.method_defined?(:pbStartBattleCore_heizo_size_fix)
      PokeBattle_Battle.class_eval do
        alias pbStartBattleCore_heizo_size_fix pbStartBattleCore
        def pbStartBattleCore(*args)
          @fullparty1 = true if @party1 && @party1.length > 6
          pbStartBattleCore_heizo_size_fix(*args)
        end
      end
    end
    
    # E. PARCHE DE NÚMEROS DE DAÑO (Heizo como compañero)
    # La función pbShowDamageNumber del motor busca @sprites["pokemon#{pkmn.index}"].
    # En batallas 2v1/2v2 con Heizo, el sprite en índice 2 puede ser nil si la escena
    # no lo inicializó, causando que las coordenadas queden nil y el número aparezca
    # en la esquina del enemigo. Este parche lo hace null-safe.
    if defined?(PokeBattle_Scene) && !PokeBattle_Scene.method_defined?(:pbShowDamageNumber_heizo_fix)
      PokeBattle_Scene.class_eval do
        alias pbShowDamageNumber_heizo_fix pbShowDamageNumber
        def pbShowDamageNumber(pkmn, oldhp, effectiveness, doublebattle, totalDamage)
          # Verificar si el sprite del battler existe antes de llamar al original
          sprite_missing = begin
            s = @sprites["pokemon#{pkmn.index}"]
            s.nil? || s.disposed? || s.bitmap.nil?
          rescue
            true
          end
          if sprite_missing
            # Sprite no disponible: calcular posición basada en el índice/bando del battler
            # índice par = bando del jugador (abajo), impar = bando del rival (arriba)
            amount  = (totalDamage != 0) ? totalDamage : (pkmn.hp - oldhp)
            gainsHp = (pkmn.hp - oldhp) > 0
            amt     = amount.abs
            text    = sprintf("%s%d", (gainsHp ? "+" : "-"), amt)
            
            # Coordenadas de fallback según bando
            if pkmn.index % 2 == 0
              # Nuestro bando (jugador / Heizo compañero) → abajo
              cx = doublebattle ? (pkmn.index == 0 ? 80 : 160) : 128
              cy = Graphics.height - 80
            else
              # Bando rival → arriba  
              cx = doublebattle ? (pkmn.index == 1 ? (Graphics.width - 80) : (Graphics.width - 160)) : (Graphics.width - 128)
              cy = (Graphics.height * 3 / 4) - 170
            end
            
            # Dibujar el número en las coordenadas calculadas
            begin
              base_color = gainsHp ? Color.new(0,204,35) : Color.new(212,176,23)
              border_color = Color.new(255,255,255)
              temp_bmp = Bitmap.new(1,1)
              pbSetSystemFont(temp_bmp)
              temp_bmp.font.size = 24
              tw = temp_bmp.text_size(text).width
              th = temp_bmp.text_size(text).height
              temp_bmp.dispose
              margin = 6
              vp = Viewport.new(0,0,Graphics.width,Graphics.height)
              vp.z = 99999
              spr = BitmapSprite.new(tw + margin*2, th + margin*2, vp)
              spr.z = vp.z + 1
              spr.ox = (tw + margin*2) / 2
              spr.oy = (th + margin*2) / 2
              spr.x = cx; spr.y = cy - 60
              pbSetSystemFont(spr.bitmap)
              spr.bitmap.font.size = 24
              spr.bitmap.font.bold = true
              pbDrawOutlineText(spr.bitmap, margin, margin, tw, th, text, base_color, border_color, 1) rescue nil
              frames = (1.5 * Graphics.frame_rate).to_i
              frames.times do
                spr.y -= 1 if spr.y > cy - 80
                Graphics.update
              end
              spr.dispose rescue nil
              vp.dispose rescue nil
            rescue; end
            return
          end
          # Si el sprite existe, llamar al método original sin problemas
          pbShowDamageNumber_heizo_fix(pkmn, oldhp, effectiveness, doublebattle, totalDamage)
        end
      end
    end

    if defined?(PokeBattle_Scene) && !PokeBattle_Scene.method_defined?(:pbEXPBar_heizo_fix)
      PokeBattle_Scene.class_eval do
        alias pbEXPBar_heizo_fix pbEXPBar
        def pbEXPBar(battler, pokemon, startexp, endexp, tempexp, realexp)
          # Si el pokemonIndex es >= 6, es de Heizo. No animamos para evitar crash/freeze.
          return if pokemon.respond_to?(:pokemonIndex) && pokemon.pokemonIndex >= 6
          # Si no tiene pokemonIndex (battler normal), verificamos el bando
          return if battler && battler.index >= 4 rescue nil 
          pbEXPBar_heizo_fix(battler, pokemon, startexp, endexp, tempexp, realexp)
        end
      end
    end
  end

  # ================================================================
  # PARCHE NUCLEAR: pbStartBattle en PokeBattle_Battle
  # Se ejecuta al inicio de CUALQUIER combate, sin importar cómo se creó.
  # Detecta si Heizo es compañero por tamaño de party (>6) y reordena
  # sus Pokémon (slots 6-11) usando puntuación de tipo ofensivo.
  # ================================================================
  if defined?(PokeBattle_Battle) && !PokeBattle_Battle.method_defined?(:pbStartBattle_heizo_lead)
    PokeBattle_Battle.class_eval do
      alias pbStartBattle_heizo_lead pbStartBattle
      def pbStartBattle(*args)
        begin
          # Activar soporte de partido extendido si Heizo está present
          @fullparty1 = true if @party1 && @party1.length > 6
          
          # Solo aplicar si hay al menos 12 Pokémon en party1 (jugador + Heizo)
          if @party1 && @party1.length > 6 && @party2 && @party2.length > 0
            heizo_sub = @party1[6..11].compact
            enemies = @party2.select { |p| p && p.hp > 0 } rescue []
            
            if heizo_sub.length > 0 && enemies.length > 0
              scored = []
              debug_log = "COMBATE INICIADO: \nEnemigo Lead: #{PBSpecies.getName(enemies[0].species)} (Type1: #{enemies[0].type1}, Type2: #{enemies[0].type2})\n\n" rescue ""
              
              heizo_sub.each_with_index do |pk, idx|
                next if !pk || pk.hp <= 0
                s = 0
                enemies.each { |en| s += pbHeizoCalculateLeadScore(pk, en) rescue 0 }
                scored.push([idx, s])
                
                sp_name = PBSpecies.getName(pk.species) rescue "Unknown"
                debug_log += "-> #{sp_name} (T1: #{pk.type1}, T2: #{pk.type2}) | Score Final: #{s}\n" rescue ""
              end
              scored.sort! { |a, b| b[1] <=> a[1] }
              
              # Reconstruir el orden
              new_order = scored.map { |item| heizo_sub[item[0]] }
              heizo_sub.each { |p| new_order.push(p) unless new_order.include?(p) }
              
              # Inyectar en party1
              new_order.each_with_index do |pk, i|
                @party1[6 + i] = pk if pk
              end
              
              debug_log += "\n=== ORDEN FINAL ===\n"
              new_order.each { |p| debug_log += "#{PBSpecies.getName(p.species)}\n" rescue "" }
              
              File.open("heizo_battle_debug.txt", "w") { |f| f.write(debug_log) } rescue nil
            end
          end
        rescue => e
          File.open("heizo_battle_debug.txt", "w") { |f| f.write("CRASH en StartBattle: #{e.message}\n#{e.backtrace.join("\n")}") } rescue nil
        end
        
        pbStartBattle_heizo_lead(*args)
      end
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
          # Respaldar la página 4 original (probablemente Cintas) como página 5
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
            @sprites["pokemon"].visible = true
            @sprites["pokeicon"].visible = false
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
                when 2; drawPageThree(@pokemon)
                when 3; drawPageMoves1(@pokemon)
                when 4; drawPageMoves2(@pokemon)
                when 5; drawPageFive(@pokemon) rescue nil
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


$pkmn_usb_dir = begin
  _usb = File.join(Dir.pwd, "Partidas Guardadas")
  Dir.mkdir(_usb) unless File.directory?(_usb)
  _usb
rescue
  nil
end

begin
  if $pkmn_usb_dir
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

    # ARRANQUE: USB -> PC (USB es la fuente portable oficial)
    if File.exist?($pkmn_usb_save)
      File.open($pkmn_pc_save, 'wb') { |w| File.open($pkmn_usb_save, 'rb') { |r| w.write(r.read) } } rescue nil
    end

    # HILO VIGILANTE: detecta guardado en PC y replica al USB
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
endcue
end
begin
  File.open('preload_test.txt', 'w') { |f| 
    f.puts("PokeBattle_Battle defined? #{defined?(PokeBattle_Battle).inspect}")
    f.puts("PokeBattle_Scene defined? #{defined?(PokeBattle_Scene).inspect}")
  }
rescue
end






# Heizo NPC - Helpers de Seguimiento
def pbHeizoFollowing?
  pbHeizoInstallBattleEvents rescue nil # Asegurar ganchos de combate
  return false if !$PokemonTemp || !$PokemonTemp.dependentEvents
  return $PokemonTemp.dependentEvents.getEventByName("HeizoNPC") != nil
end

# Registra al evento estático de Heizo (ID 995) en el sistema DependentEvents
# para que siga al jugador por el mapa.
def pbStartHeizoFollowing
  return if !$PokemonTemp || !$PokemonTemp.dependentEvents
  return if pbHeizoFollowing? # Ya está siguiendo, nada que hacer

  # Obtener o crear el evento estático en el mapa actual
  heizo_event = $game_map.events[995] rescue nil

  if !heizo_event
    # Si aún no existe (mapa sin spawn), lo creamos junto al jugador
    begin
      px = $game_player.x
      py = $game_player.y + 1
      re = RPG::Event.new(px, py)
      re.id = 995
      re.name = "HeizoNPC"
      page = RPG::Event::Page.new
      page.graphic.character_name = "cazadorow"
      page.graphic.direction = 2
      page.graphic.opacity = 255
      page.trigger = 0
      page.list = [
        RPG::EventCommand.new(355, 0, ["Kernel.pbHeizoDialog"]),
        RPG::EventCommand.new(0, 0, [])
      ]
      re.pages = [page]
      heizo_event = Game_Event.new($game_map.map_id, re, $game_map)
      $game_map.events[995] = heizo_event
      heizo_event.refresh
    rescue
      return
    end
  end

  begin
    # addEvent registra en $PokemonGlobal.dependentEvents y llama a event.erase
    $PokemonTemp.dependentEvents.addEvent(heizo_event, "HeizoNPC", nil)
    # Limpiar el slot estático para evitar duplicado visual
    $game_map.events.delete(995) rescue nil
    $heizo_spawned = false
  rescue
  end
end

# Elimina a Heizo del sistema DependentEvents y reactiva el spawn estático.
def pbStopHeizoFollowing
  return if !$PokemonTemp || !$PokemonTemp.dependentEvents
  begin
    $PokemonTemp.dependentEvents.removeEventByName("HeizoNPC")
    $game_map.events.delete(995) rescue nil
    $heizo_spawned = false # Permitir re-spawn estático en el próximo frame
  rescue
  end
end

# Heizo NPC - Integrado directamente
$heizo_maps = [10, 18, 30, 45, 60, 82, 104, 114, 134, 142, 164]
$heizo_last_map = 0
$heizo_spawned = false

module Graphics
  class << self
    alias heizo_upd_final update
    def update
      heizo_upd_final
      # Crear Heizo inmediatamente al cargar el mapa
      spawn_heizo_final
      
      # Parche en tiempo de ejecución para evitar problemas de orden de carga
      if !@heizo_patched_player
        if defined?(::Game_Player)
          @heizo_patched_player = true
          ::Game_Player.class_eval do
            if !method_defined?(:heizo_old_character_name)
              alias heizo_old_character_name character_name
              def character_name
                # Si los ropajes están activos y no estamos en bici/surf/buceo
                if $game_variables && $game_variables[994] == 1
                  if $PokemonGlobal && !$PokemonGlobal.bicycle && !$PokemonGlobal.surfing && !$PokemonGlobal.diving
                    return "cazadorow"
                  end
                end
                # Comportamiento normal
                return heizo_old_character_name
              end
            end

            # Parche para poder hablarle al seguidor Heizo
            if !method_defined?(:heizo_check_event_trigger_there)
              alias heizo_check_event_trigger_there check_event_trigger_there
              def check_event_trigger_there(triggers)
                # 1. Comprobar eventos normales (estáticos)
                ret = heizo_check_event_trigger_there(triggers)
                return ret if ret
                
                # 2. Si no hay evento normal en frente, comprobar seguidores de Heizo
                return false if $game_system.map_interpreter.running?
                if triggers.include?(0) # Botón Acción (C)
                  # Comprobamos hasta 3 tiles en frente para encontrar a Heizo en la fila
                  for dist in 1..3
                    new_x = @x + (@direction == 6 ? dist : @direction == 4 ? -dist : 0)
                    new_y = @y + (@direction == 2 ? dist : @direction == 8 ? -dist : 0)
                    
                    if $PokemonTemp && $PokemonTemp.dependentEvents
                      evts = $PokemonTemp.dependentEvents.realEvents rescue []
                      data_list = $PokemonGlobal.dependentEvents rescue []
                      for i in 0...data_list.length
                        event = evts[i]
                        data = data_list[i]
                        if event && event.x == new_x && event.y == new_y && data && data[8] == "HeizoNPC"
                          Kernel.pbHeizoDialog
                          return true
                        end
                      end
                    end
                  end
                end
                return false
              end
            end
          end
        end
      end
      
      if !@heizo_patched_dependent
        if defined?(::DependentEvents)
          @heizo_patched_dependent = true
          ::DependentEvents.class_eval do
            if !method_defined?(:heizo_createEvent)
              alias heizo_createEvent createEvent
              def createEvent(eventData)
                newEvent = heizo_createEvent(eventData)
                
                # REGLA GENERAL: Ocultar si surfeamos, buceamos o vamos en bici
                if $PokemonGlobal && ($PokemonGlobal.surfing || $PokemonGlobal.diving || $PokemonGlobal.bicycle)
                  newEvent.transparent = true rescue nil
                  newEvent.opacity = 0 rescue nil
                end

                if eventData[8] == "HeizoNPC"
                  list = [
                    RPG::EventCommand.new(355, 0, ["Kernel.pbHeizoDialog"]),
                    RPG::EventCommand.new(0, 0, [])
                  ]
                  rpg_evt = newEvent.instance_variable_get(:@event)
                  rpg_evt.pages[0].list = list if rpg_evt && rpg_evt.respond_to?(:pages) && rpg_evt.pages && rpg_evt.pages[0]
                  if newEvent.respond_to?(:refresh)
                    newEvent.refresh
                  end
                end
                return newEvent
              end
            end

            if !method_defined?(:heizo_refresh_sprite)
              alias heizo_refresh_sprite refresh_sprite
              def refresh_sprite(animation=false)
                heizo_refresh_sprite(animation)
                
                # Sincronizar visibilidad por medio de transporte
                hide_all = $PokemonGlobal && ($PokemonGlobal.surfing || $PokemonGlobal.diving || $PokemonGlobal.bicycle)
                
                evts = @realEvents rescue []
                for evt in evts
                  next if !evt
                  if hide_all
                    evt.transparent = true rescue nil
                    evt.opacity = 0 rescue nil
                  else
                    evt.transparent = false rescue nil
                    evt.opacity = 255 rescue nil
                  end
                end
              end
            end

            if !method_defined?(:heizo_update_dep)
              alias heizo_update_dep updateDependentEvents
              def updateDependentEvents
                heizo_update_dep
                # REGLA SIMPLE: Ocultar todo si se surfea, bucea o va en bici (sin lag)
                is_surfing = $PokemonGlobal && $PokemonGlobal.surfing rescue false
                is_diving = $PokemonGlobal && $PokemonGlobal.diving rescue false
                is_biking = $PokemonGlobal && $PokemonGlobal.bicycle rescue false
                hide_all = is_surfing || is_diving || is_biking
                
                evts = (@realEvents || []) rescue []
                if hide_all
                  for evt in evts
                    next if !evt
                    evt.transparent = true rescue nil
                    evt.opacity = 0 rescue nil
                  end
                else
                  # Restaurar visibilidad normal en tierra firme
                  for evt in evts
                    next if !evt
                    # Solo tocamos transparencia si no hay otro sistema (como invisibilidad)
                    evt.transparent = $game_player.transparent rescue false
                    evt.opacity = 255 rescue nil
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

def spawn_heizo_final
  return if !$game_map
  
  # SI ESTÁ SIGUIENDO, ELIMINAR EL CLON ESTÁTICO
  if pbHeizoFollowing?
    if $game_map.events[995]
      # Borramos el evento y su representación
      $game_map.events.delete(995) rescue nil
      $heizo_spawned = false
    end
    return
  end

  current_map = $game_map.map_id
  
  if current_map != $heizo_last_map
    $heizo_last_map = current_map
    $heizo_spawned = false
  end
  
  return if !$heizo_maps.include?(current_map)
  return if $heizo_spawned
  return if $game_map.events[995]
  
  # Posición fija (3, 11) (5 más a la izquierda de la anterior (8,11))
  x, y = 3, 11
  
  begin
    re = RPG::Event.new(x, y)
    re.id = 995
    re.name = "HeizoNPC"
    
    page = RPG::Event::Page.new
    page.graphic.character_name = "cazadorow"
    page.graphic.direction = 2
    page.graphic.opacity = 255
    page.trigger = 0
    
    # Configuración de movimiento (comentado)
    # page.move_type = 1        # 0=fijo, 1=aleatorio, 2=hacia jugador, 3=custom
    # page.move_speed = 2       # Velocidad: 1=lento, 2=normal, 3=rapido, 4=muy rápido
    # page.move_frequency = 2    # Frecuencia: 1=baja, 2=normal, 3=alta
    # page.walk_anime = true   # Animación al caminar
    # page.step_anime = false  # Animación al detenerse
    # page.direction_fix = false # Fijar dirección
    # page.through = false     # Atravesar
    # page.always_on_top = false # Siempre encima
    
    # Configuración de sombra (comentado - para añadir sombra)
    # page.graphic.character_name = "cazadorow/noShadow"  # Para quitar sombra
    
    page.list = [
      RPG::EventCommand.new(355, 0, ["Kernel.pbHeizoDialog"]),
      RPG::EventCommand.new(0, 0, [])
    ]
    
    re.pages = [page]
    
    ge = Game_Event.new($game_map.map_id, re, $game_map)
    $game_map.events[995] = ge
    ge.refresh
    
    # Añadir sombra específica para Heizo
    if $scene.is_a?(Scene_Map) && $scene.spriteset
      begin
        vp = $scene.spriteset.instance_variable_get(:@viewport1)
        if vp
          # Crear sprite y sombra al mismo tiempo
          spr = Sprite_Character.new(vp, ge)
          arr = $scene.spriteset.instance_variable_get(:@character_sprites)
          arr.push(spr) if arr
          
          # Crear sombra para Heizo inmediatamente
          heizo_shadow = ShadowSprite.new(spr, ge, vp, $game_map, "HeizoNPC", true)
          shadow_sprites = $scene.spriteset.instance_variable_get(:@shadowSprites) rescue []
          shadow_sprites.push(heizo_shadow) if shadow_sprites
        end
      rescue => e
        Kernel.pbMessage("Error al crear sombra para Heizo: #{e.message}")
      end
    end
    
    $heizo_spawned = true
  rescue
  end
end


# Funcion de dialogo para Heizo
module Kernel
  def self.pbHeizoDialog
    # Asegurar que los overrides de combate se instalen (solo una vez)
    pbHeizoInstallBattleOverrides rescue nil

    # 1. Definir HeizoBattle de forma dinámica para evitar errores de carga (NameError)
    if !defined?(::HeizoBattle)
      heizo_cls = Class.new(::PokeBattle_Battle) do
        # --- IA PERSONALIZADA PARA HEIZO ---
        
        # Función de Puntuación Avanzada (Ofensiva y Defensiva)
        def pbHeizoScorePokemon(pkmn, opponent)
          score = 0
          # PUNTUACIÓN OFENSIVA: Basada en la efectividad de sus movimientos contra el rival activo
          for move in pkmn.moves
            next if !move || move.id == 0
            begin
              eff = PBTypes.getCombinedEffectiveness(move.type, opponent.type1, opponent.type2)
            rescue
              eff = 8 # Normal
            end
            score += eff
            score += 4 if pkmn.hasType?(move.type) && eff > 8 # Bonus STAB
          end

          # PUNTUACIÓN DEFENSIVA: Resistencias de Heizo contra los tipos del rival
          [opponent.type1, opponent.type2].each do |t|
            next if t.nil? || t < 0
            begin
              res = PBTypes.getCombinedEffectiveness(t, pkmn.type1, pkmn.type2)
              if res == 0;      score += 20 # Inmunidad
              elsif res < 8;    score += 12 # Resistencia
              elsif res > 12;   score -= 15 # Debilidad Crítica
              end
            rescue
            end
          end
          score += (pkmn.hp * 15 / pkmn.totalhp).to_i if pkmn.totalhp > 0
          return score
        end

        # Selección de Lead Inteligente (Soportar Individual, Doble, Jefe o Compañero)
        def pbStartBattle(*args)
          # Detectar en qué bando y qué índice de entrenador está Heizo
          heizo_side = -1; heizo_t_idx = -1
          for side in 0..1
            for i in 0...(@trainers[side].length rescue 0)
              if @trainers[side][i] && @trainers[side][i].name == "Heizo"
                heizo_side = side; heizo_t_idx = i; break
              end
            end
            break if heizo_side >= 0
          end

          if heizo_side >= 0
            # Mi equipo
            my_party = pbParty(heizo_side)
            # Identificar oponentes (el bando contrario)
            opp_side = 1 - heizo_side
            opp_party = pbParty(opp_side).select { |p| p && p.hp > 0 && !p.isEgg? }
            
            if opp_party.length > 0
              candidates = []
              num_leads = @doublebattle ? 2 : 1
              opp_leads = opp_party[0...num_leads]
              
              # Ajuste: Si Heizo es compañero (side 0), sus Pokémon suelen estar tras los del jugador (offset 6)
              # Si es el oponente principal (side 1), el offset es 0.
              start_idx = (heizo_side == 0 && @trainers[0].length > 1) ? 6 : 0
              end_idx = start_idx + 5
              
              sub_party = my_party[start_idx..end_idx] || []
              
              sub_party.each_with_index do |pkmn, i|
                next if !pkmn || pkmn.hp <= 0 || pkmn.isEgg?
                t_score = 0
                opp_leads.each { |ol| t_score += pbHeizoScorePokemon(pkmn, ol) }
                candidates.push([i, t_score / opp_leads.length])
              end
              
              candidates.sort! { |a, b| b[1] <=> a[1] }
              
              if candidates.length > 0
                new_sub = []
                tops = candidates[0...num_leads].map { |c| c[0] }
                tops.each { |idx| new_sub.push(sub_party[idx]) }
                sub_party.each_with_index { |p, idx| new_sub.push(p) unless tops.include?(idx) }
                
                # Reinyectar en la party principal para que el juego saque al mejor lead
                for i in 0..5
                  my_party[start_idx + i] = new_sub[i] if new_sub[i]
                end
              end
            end
          end
          super(*args)
        end

        # Cambio por Derrota con Factor de Caos
        def pbChooseBestNewEnemy(index, party, enemies)
          return -1 if !enemies || enemies.length == 0
          opponent = @battlers[index].pbOppositeOpposing
          opponent = opponent.pbPartner if opponent.isFainted?
          return super if !opponent || opponent.isFainted?
          scored_enemies = []
          for e in enemies
            score = pbHeizoScorePokemon(party[e], opponent)
            scored_enemies.push([e, score])
          end
          scored_enemies.sort! { |a, b| b[1] <=> a[1] }
          if scored_enemies.length > 1 && pbAIRandom(100) < 20
            return scored_enemies[1][0]
          end
          return scored_enemies[0][0]
        end

        # --- IA ESTRATÉGICA FINAL (COMBOS Y TÁCTICAS) ---
        def pbGetMoveScore(move, attacker, opponent, score=5)
          score = super
          
          # 1. Combo de Sueño (Hipnosis, Espora, Yoste)
          hip_id = getID(PBMoves, :HYPNOSIS) rescue 95
          spo_id = getID(PBMoves, :SPORE) rescue 147
          yawn_id = getID(PBMoves, :YAWN) rescue 281
          
          if [hip_id, spo_id, yawn_id].include?(move.id)
            if opponent.status == 0 && opponent.pbCanSleep?(attacker, false)
              score += 100 # Prioridad máxima a dormir
            else
              score -= 100 # No intentar si ya tiene estado
            end
          end

          # 2. Capitalización de Sueño (Comer Sueños, Pesadilla)
          dream_id = getID(PBMoves, :DREAMEATER) rescue 138
          night_id = getID(PBMoves, :NIGHTMARE) rescue 171
          if [dream_id, night_id].include?(move.id)
            if opponent.status == PBStatuses::SLEEP
              score += 120 # Castigo severo si duerme
            else
              score -= 120 # Inútil si está despierto
            end
          end

          # 3. Hazards (Trampa Rocas)
          rock_id = getID(PBMoves, :STEALTHROCK) rescue 446
          if move.id == rock_id
            if opponent.pbOwnSide.effects[PBEffects::StealthRock]
              score -= 100
            else
              score += 50 if attacker.turncount < 3
            end
          end

          # 4. Recuperación (Respiro, Síntesis, Gigadrenado, Drenadoras)
          # Roost=435, Synthesis=232, Giga Drain=202, Leech Seed=73
          recovery = [(getID(PBMoves, :ROOST) rescue 435), 
                      (getID(PBMoves, :SYNTHESIS) rescue 232), 
                      (getID(PBMoves, :GIGADRAIN) rescue 202),
                      (getID(PBMoves, :LEECHSEED) rescue 73)]
          if recovery.include?(move.id)
            if attacker.hp < attacker.totalhp / 2
              score += 40
            end
          end

          # 5. Mismo Destino (Destiny Bond) - Destiny Bond=194
          destiny_id = getID(PBMoves, :DESTINYBOND) rescue 194
          if move.id == destiny_id
            if attacker.hp < attacker.totalhp / 3
              score += 80 # Intentar llevarse al rival si va a morir
            end
          end

          # 6. Targeting Inteligente (Dobles) - Priorizar remates para superioridad numérica
          if @doublebattle && opponent && opponent.hp < (opponent.totalhp / 3)
            score += 40
          end

          return score
        end

        # Cambios Proactivos (IA Inteligente y Justa)

        def pbEnemyShouldWithdrawEx?(index, alwaysSwitch)
          return true if alwaysSwitch
          battler = @battlers[index]
          return false if battler.turncount <= 0
          
          # Encontrar oponentes activos (Soporta Individual y Dobles)
          active_opponents = []
          opp1 = battler.pbOppositeOpposing
          active_opponents.push(opp1) if opp1 && !opp1.isFainted?
          opp2 = (opp1 && opp1.pbPartner) ? opp1.pbPartner : nil
          active_opponents.push(opp2) if opp2 && !opp2.isFainted?
          
          return false if active_opponents.empty?
          
          begin
            # 1. FILTRO DE KO: Si ALGÚN rival está herido y tenemos ventaja ofensiva, nos quedamos.
            for opp in active_opponents
              if opp.hp < opp.totalhp * 0.75
                for m in battler.moves
                  next if !m || m.id == 0 || m.basedamage == 0
                  eff = PBTypes.getCombinedEffectiveness(m.type, opp.type1, opp.type2)
                  if eff > 12 # Súper efectivo
                    return false if pbAIRandom(100) < 80 # 80% de quedarse a intentar el KO
                  end
                end
              end
            end

            # 2. FACTOR DE AGALLAS (30% de quedarse por pura agresividad)
            return false if pbAIRandom(100) < 30

            # 3. FILTRO "FODDER" (Sacrificio táctico)
            # Solo si el rival más rápido puede matarnos
            fastest_opp = active_opponents.max_by { |o| o.speed }
            if battler.hp < (battler.totalhp / 4) && battler.speed < fastest_opp.speed
              return false 
            end

            # 4. CONCIENCIA DE AMENAZA DUAL
            # Buscamos si CUALQUIERA de los oponentes tiene una ventaja de tipo crítica
            main_threat = nil
            for opp in active_opponents
              eff1 = PBTypes.getCombinedEffectiveness(opp.type1, battler.type1, battler.type2)
              eff2 = (opp.type1 != opp.type2) ? PBTypes.getCombinedEffectiveness(opp.type2, battler.type1, battler.type2) : 0
              if eff1 > 12 || eff2 > 12
                main_threat = opp
                break
              end
            end
            
            # Solo buscamos cambio si detectamos una amenaza seria
            if main_threat
              party = pbParty(index)
              current_score = pbHeizoScorePokemon(battler.pokemon, main_threat)
              
              best_bench_index = -1
              max_bench_score = current_score

              for i in 0...party.length
                next if !pbCanSwitch?(index, i, false)
                # Puntuación contra la amenaza principal
                bench_score = pbHeizoScorePokemon(party[i], main_threat)
                if bench_score > max_bench_score
                  max_bench_score = bench_score
                  best_bench_index = i
                end
              end
              
              # UMBRAL DE VENTAJA: Solo cambia si el banquillo es sustancialmente mejor contra la amenaza
              if best_bench_index != -1 && max_bench_score > current_score + 50
                return pbRegisterSwitch(index, best_bench_index)
              end
            end
          rescue
          end
          return super
        end

      end # end Class.new block
      Object.const_set(:HeizoBattle, heizo_cls)
    end # end if !defined?

    # 2. Hook de Diálogo Robusto a nivel de Battler (v5 - Versión con Memoria Antiduplicados)
    battler_class = defined?(::PokeBattle_Battler) ? ::PokeBattle_Battler : (defined?(::Battle::Battler) ? ::Battle::Battler : nil)
    if battler_class && !battler_class.method_defined?(:pbFaint_heizo_v5)
      battler_class.class_eval do
        alias pbFaint_heizo_v5 pbFaint
        def pbFaint(*args)
          # 1. Ejecutar desmayo original primero
          pbFaint_heizo_v5(*args)
          
          # 2. Verificación de combate de Heizo y bando rival
          return if !@battle || !@battle.instance_variable_get(:@heizo_battle) || self.index % 2 == 0
          
          # COMPROBACIÓN DE BANDO: Si Heizo es compañero (lado 0), NO decir frases de derrota
          heizo_is_partner = false
          ((@battle.player.is_a?(Array) ? @battle.player : [@battle.player]) rescue []).each do |t|
            heizo_is_partner = true if t && t.name == "Heizo"
          end
          return if heizo_is_partner # Heizo no llora si está en nuestro equipo
          
          # 3. Contar derrotados actualmente
          party = @battle.pbParty(1)
          derrotados = 0
          for p in party; derrotados += 1 if p && p.hp <= 0; end
          
          # 4. SISTEMA ANTIDUPLICADOS: Solo disparar si el contador ha subido
          # Esto evita que se repita el diálogo si el motor llama a pbFaint varias veces para el mismo Pokémon
          last_processed = @battle.instance_variable_get(:@heizo_last_count) || 0
          return if derrotados <= last_processed
          @battle.instance_variable_set(:@heizo_last_count, derrotados)
          
          # 5. Selección de mensaje (PRIORIDAD: ESPECIES)
          char_id = getID(PBSpecies, :CHARIZARD) rescue nil
          ven_id  = getID(PBSpecies, :VENUSAUR) rescue nil
          gen_id  = getID(PBSpecies, :GENGAR) rescue nil
          zer_id  = getID(PBSpecies, :ZERAORA) rescue nil
          cor_id  = getID(PBSpecies, :CORVIKNIGHT) rescue nil
          swa_id  = getID(PBSpecies, :SWAMPERT) rescue nil
          
          sp = self.pokemon ? self.pokemon.species : (self.respond_to?(:species) ? self.species : 0)
          msg = nil
          
          # Prioridad absoluta a las frases de especie solicitadas
          case sp
          when char_id; msg = "Heizo: Ni siquiera las llamas del inframundo han bastado... empiezas a interesarme."
          when ven_id;  msg = "Heizo: Has superado incluso a mis toxinas."
          when gen_id;  msg = "Heizo: ¿Crees que derrotar a una sombra te hace fuerte? Solo estás retrasando lo inevitable."
          when zer_id;  msg = "Heizo: ¿Has podido seguir la velocidad del rayo? Impresionante."
          when cor_id;  msg = "Heizo: Ni siquiera la armadura más pesada es eterna... bien hecho."
          when swa_id;  msg = "Heizo: El lodo se ha secado... pero tu esfuerzo ha sido digno."
          end
          
          # Si no es ninguna de esas especies (fallback de seguridad por conteo)
          if msg.nil?
            if derrotados == party.length
              msg = "Heizo: Increíble... me has vencido limpiamente."
            elsif derrotados == 1
              msg = "Heizo: ¡Vaya! No esperaba que derrotaras a mi primer Pokémon tan rápido."
            end
          end

          # 6. Mostrar Diálogo Cinemático
          if msg
            if @battle.scene.respond_to?(:pbShowOpponent)
              @battle.scene.pbShowOpponent(0) rescue nil
              @battle.pbDisplayPaused(_INTL(msg))
              @battle.scene.pbHideOpponent rescue nil
            else
              @battle.pbDisplayPaused(_INTL(msg))
            end
            ::Graphics.update; pbWait(5) if defined?(pbWait)
          end
        end
      end
    end

    # 3. Hook de Entrada de Pokémon (v1 - Diálogos al salir)
    if !::PokeBattle_Battle.method_defined?(:pbSendOut_heizo_v1)
      ::PokeBattle_Battle.class_eval do
        alias pbSendOut_heizo_v1 pbSendOut
        def pbSendOut(index, pokemon)
          # Ejecutar el comando de salida original
          pbSendOut_heizo_v1(index, pokemon)
          
          # Solo si es combate de Heizo, es un Pokémon rival (índice impar), Y Heizo es el JEFE (no compañero)
          heizo_is_partner_send = false
          ((self.player.is_a?(Array) ? self.player : [self.player]) rescue []).each { |t| heizo_is_partner_send = true if t && t.name == "Heizo" }
          if self.instance_variable_get(:@heizo_battle) && index % 2 != 0 && !heizo_is_partner_send
            char_id = getID(PBSpecies, :CHARIZARD) rescue nil
            ven_id  = getID(PBSpecies, :VENUSAUR) rescue nil
            gen_id  = getID(PBSpecies, :GENGAR) rescue nil
            zer_id  = getID(PBSpecies, :ZERAORA) rescue nil
            cor_id  = getID(PBSpecies, :CORVIKNIGHT) rescue nil
            swa_id  = getID(PBSpecies, :SWAMPERT) rescue nil
            
            msg = nil
            case pokemon.species
            when char_id; msg = "Heizo: ¡Charizard! ¡Surca los cielos y reduce todo a cenizas con tu fuego ancestral!"
            when ven_id;  msg = "Heizo: ¡Venusaur! ¡Despliega tus toxinas y que la naturaleza reclame lo que es suyo!"
            when gen_id;  msg = "Heizo: ¡Gengar! ¡Sal de las sombras y arrastra a nuestro oponente a la oscuridad eterna!"
            when zer_id;  msg = "Heizo: ¡Zeraora! ¡Demuéstrales que nada es más rápido que el trueno!"
            when cor_id;  msg = "Heizo: ¡Corviknight! ¡Despliega tus alas de acero y sé nuestro escudo inquebrantable!"
            when swa_id;  msg = "Heizo: ¡Swampert! ¡Desata la fuerza de las mareas y que la tierra tiemble ante tu poder!"
            end
            
            if msg
              if @scene.respond_to?(:pbShowOpponent)
                @scene.pbShowOpponent(0) rescue nil
                pbDisplayPaused(_INTL(msg))
                @scene.pbHideOpponent rescue nil
              else
                pbDisplayPaused(_INTL(msg))
              end
              ::Graphics.update; pbWait(5) if defined?(pbWait)
            end
          end
        end
      end
    end

    # Identificar el evento (estático o seguidor)
    heizo_event = $game_map.events[995]
    
    # --- AUTO-SINCRO MERCENARIO (SOLO LÓGICA INTERNA) ---
    # Nota: No usamos $PokemonGlobal.partner para evitar que el motor fuerce 2v2 automáticamente.
    if pbHeizoFollowing? && $game_variables[992] == 1
      if pbHeizoInGym?
        # Desactivar apoyo si estamos en un gimnasio
        $game_variables[992] = 0 rescue nil
      end
    end
    if !heizo_event && $PokemonTemp && $PokemonTemp.dependentEvents
       heizo_event = $PokemonTemp.dependentEvents.getEventByName("HeizoNPC")
    end
    
    # EFECTO VISUAL Y SONORO DE ATENCIÓN
    if heizo_event
      if !pbHeizoFollowing?
        # Solo mostrar exclamación si NO está siguiendo (estático)
        fake_event = Struct.new(:x, :y).new(heizo_event.x, heizo_event.y - 1)
        pbExclaim(fake_event, 3) rescue nil 
      end
      pbSEPlay("VozCrisantoWhat") rescue nil
    end

    if $game_variables[995] == 0
      # --- MÚSICA DE ENCUENTRO ---
      pbBGMPlay("Acertijos") # MÚSICA PARA DIÁLOGOS DE HEIZO
      # Capturar ubicación del encuentro original
      $game_variables[996] = $game_map.map_id
      $game_variables[997] = [$game_player.x, $game_player.y, $game_player.direction]
      $game_variables[998] = [heizo_event.x, heizo_event.y, heizo_event.direction] if heizo_event
      
      pbMessage(_INTL("..."))
      pbMessage(_INTL("Soy Heizo. El creador de este Mod."))
      pbMessage(_INTL("No vine a hacer amigos. Vine a desafiar."))
      pbMessage(_INTL("Si me vences, te abro las puertas de mi mercado negro."))
      
      if pbConfirmMessage(_INTL("Acepto el desafío"))
        pbMessage(_INTL("Bien. Prepara tu equipo. No empezaremos aún."))
        pbMessage(_INTL("Me quedaré aquí con mi hidromiel. Habla conmigo cuando estés listo."))
        $game_variables[995] = 1
      else
        pbMessage(_INTL("..."))
        pbMessage(_INTL("Como esperaba. Vuelve cuando te atrevas."))
        $game_map.autoplay # Restaurar música del mapa al rechazar
      end
      $game_map.autoplay if $game_variables[995] == 1
      return
    
    # ESTADO 1: Esperando confirmación para luchar
    elsif $game_variables[995] == 1
      if pbConfirmMessage(_INTL("¿Estás listo para el combate?"))
        # Elegir Modo de Combate (Menú de Selección)
        cmd_mode = pbMessage(_INTL("Heizo: ¿Cómo prefieres combatir?"), [
          _INTL("Individual"),
          _INTL("Doble")
        ], 0)
        is_double = (cmd_mode == 1)

        if is_double
          # Comprobación de seguridad: ¿Tiene el jugador al menos 2 Pokémon sanos?
          player_healthy = $Trainer.party.count { |p| p && p.hp > 0 && !p.isEgg? }
          if player_healthy < 2
            pbMessage(_INTL("Heizo: Tipo, es imposible que me ganes así... no perdamos el tiempo."))
            pbMessage(_INTL("Heizo: Vuelve cuando tengas al menos dos Pokémon en condiciones."))
            $game_map.autoplay; return
          end
        end

        pbMessage(_INTL("Heizo: Bien. Que empiece."))
        
        if heizo_event
          pbMoveRoute($game_player, [
            PBMoveRoute::ChangeSpeed, 2, 
            PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right
          ])
          pbMoveRoute(heizo_event, [
            PBMoveRoute::ChangeSpeed, 2, 
            PBMoveRoute::Wait, 32, # Esperar un poco para "tardar en activarse"
            PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right
          ], true) 
        end
        pbWait(40) 

        # 1. Crear fundido a negro MANUAL (para evitar microcortes y pantalla negra perpetua)
        black_vp = Viewport.new(0,0,Graphics.width,Graphics.height)
        black_vp.z = 999999
        col = Color.new(0,0,0,0)
        for j in 0..17
          col.set(0,0,0,j*15); black_vp.color = col
          Graphics.update; Input.update
        end

        # 2. RESETAR FÍSICAS y Teletransporte INVISIBLE (mientras está en negro)
        # Limpiamos estados forzados para recuperar colisiones y físicas
        $game_player.instance_variable_set(:@through, false)
        $game_player.instance_variable_set(:@move_route_forcing, false)
        $game_player.instance_variable_set(:@walk_anime, true)
        
        if heizo_event
          heizo_event.instance_variable_set(:@through, false)
          heizo_event.instance_variable_set(:@move_route_forcing, false)
          heizo_event.instance_variable_set(:@walk_anime, true)
        end
        
        p_pos = $game_variables[997]
        h_pos = $game_variables[998]
        
        $game_player.moveto(p_pos[0], p_pos[1])
        $game_player.instance_variable_set(:@direction, p_pos[2])
        if heizo_event
          heizo_event.moveto(h_pos[0], h_pos[1])
          heizo_event.instance_variable_set(:@direction, h_pos[2])
        end
        
        # Un pequeño refresco del mapa nos asegura que el cambio "se vea" al quitar el negro
        $game_map.need_refresh = true
        $game_player.straighten
 
        # 3. Preparar equipo de Heizo
        max_level = $Trainer.party.map { |p| p.level }.max || 5
        heizo_opponent = PokeBattle_Trainer.new("Heizo", 35) 
        heizo_opponent.party = pbGetHeizoTeam(max_level)
        
        # 4. Iniciar animación y combate
        bgm = "CombateLider" # MÚSICA DE COMBATE LÍDER
        $PokemonGlobal.nextBattleBack = "Pantano"
        
        $game_player.straighten
        heizo_event.straighten if heizo_event
        
        decision = 0
        pbBattleAnimation(bgm) { 
          # ELIMINAR EL NEGRO justo cuando empieza la transición de batalla
          black_vp.dispose
          
          scene = pbNewBattleScene
          # USAR LA ETIQUETA HEIZO BATTLE DESDE EL PRIMER COMBATE
          battle = HeizoBattle.new(scene, $Trainer.party, heizo_opponent.party, $Trainer, heizo_opponent)
          battle.doublebattle = is_double
          battle.instance_variable_set(:@heizo_battle, true) # ETIQUETA ROBUSTA
          battle.instance_variable_set(:@endspeech, "No es posible... mi magnífico equipo ha caído. No esperaba que alguien pudiera superar tal grado de maestría.") # FIX CAJA VACIA
          battle.internalbattle = true
          pbPrepareBattle(battle)
          pbSceneStandby { decision = battle.pbStartBattle }
        }
        
        # 5. Manejo de resultados
        $game_player.instance_variable_set(:@through, false)
        $game_player.instance_variable_set(:@move_route_forcing, false)
        heizo_event.instance_variable_set(:@through, false) if heizo_event
        heizo_event.instance_variable_set(:@move_route_forcing, false) if heizo_event
        $game_player.straighten
        heizo_event.straighten if heizo_event
        
        if decision == 1 # Victoria
          pbMessage(_INTL("Heizo: Has ganado. El mercado negro es tuyo."))
          pbMessage(_INTL("Heizo: Estaré aquí con mi hidromiel. Cuando quieras, vuelve."))
          
          # Cambiamos a Estado 2 (Victoria/Tienda desbloqueada)
          $game_variables[995] = 2 
        else
          pbMessage(_INTL("Heizo: Bien jugado. He ganado esta vez."))
          pbStartOver
        end
        
        # Volver a la mesa y forzar posición inicial (solo si no es seguidor)
        h_pos = $game_variables[998]
        if !pbHeizoFollowing? && heizo_event && h_pos
          heizo_event.moveto(h_pos[0], h_pos[1])
          heizo_event.instance_variable_set(:@direction, h_pos[2])
        end
        return
      else
        pbMessage(_INTL("Bien. Veamos si tu preparación ha servido de algo."))
        $game_map.autoplay # Restaurar música del mapa al no querer combatir
        return
      end

    # ESTADO 2: MENÚ POST-DERROTA (Elección entre Luchar o Comprar)
    elsif $game_variables[995] == 2
      pbBGMPlay("Acertijos") # MÚSICA PARA DIÁLOGOS
        # Aseguramos posición inicial en la mesa (solo si NO está siguiendo)
        h_pos = $game_variables[998]
        if !pbHeizoFollowing? && heizo_event && h_pos
          heizo_event.moveto(h_pos[0], h_pos[1])
          heizo_event.instance_variable_set(:@direction, h_pos[2])
        end

        pbMessage(_INTL("Heizo: El campeón. ¿Qué necesitas?"))
        
        $heizo_following = pbHeizoFollowing?
        follow_label = $heizo_following ? _INTL("Vuelve al Centro Pokémon") : _INTL("Acompáñame")
        
        main_choices = []
        if $heizo_following
          # Menú de Seguidor con opciones de mercenario
          main_choices << _INTL("Mercado Negro")
          if $game_variables[992] == 1
            main_choices << _INTL("Cambiar Táctica")
            main_choices << _INTL("Retirar Apoyo en Combate")
          else
            main_choices << _INTL("Acuerdo de Combate ($10,000)")
          end
          main_choices << _INTL("Cambiar Ropa")
          main_choices << follow_label
          main_choices << _INTL("Nada por ahora")
        else
          # Menú Estático
          main_choices << _INTL("Combatir de nuevo")
          main_choices << _INTL("Mercado Negro")
          main_choices << follow_label
          main_choices << _INTL("Nada por ahora")
        end
        
        cmd = pbMessage(_INTL("Heizo: El campeón. ¿Qué necesitas?"), main_choices, main_choices.length - 1)

        if $heizo_following
          # --- LÓGICA MENÚ SEGUIDOR ---
          case main_choices[cmd]
          when _INTL("Mercado Negro")
            # Salta al bloque de Mercado Negro abajo
          when _INTL("Acuerdo de Combate ($10,000)")
            if pbHeizoInGym?
              pbMessage(_INTL("Heizo: Aquí chaval te lo curras tú. No te voy a ayudar aquí, que tienes que mostrar tu valía."))
            else
              pbMessage(_INTL("Heizo: Si quieres, te ayudo en combate con mis Pokémon. Te ofrezco mi servicio por 10.000$."))
              if pbConfirmMessage(_INTL("¿Contratar el apoyo de Heizo por 10.000$?"))
                if $Trainer.money >= 10000
                  $Trainer.money -= 10000
                  $game_variables[992] = 1
                  # Elegir táctica inicial
                  t = pbMessage(_INTL("Heizo: ¿Cómo quieres mi ayuda en la naturaleza?"), 
                                [_INTL("Dúo de Apoyo (2 vs 1)"), _INTL("Caza Doble (2 vs 2)")], 0)
                  $game_variables[991] = t
                  pbMessage(_INTL("Heizo: Trato hecho. Mis Pokémon están a tu disposición."))
                else
                  pbMessage(_INTL("Heizo: No tienes suficiente. No soy un mercenario barato."))
                end
              end
            end
            $game_map.autoplay; return
          when _INTL("Cambiar Táctica")
            t = pbMessage(_INTL("Heizo: ¿Qué táctica prefieres para la hierba alta?"), 
                          [_INTL("Dúo de Apoyo (2 vs 1)"), _INTL("Caza Doble (2 vs 2)")], $game_variables[991])
            $game_variables[991] = t
            pbMessage(_INTL("Heizo: Cambiando táctica... listo."))
            $game_map.autoplay; return
          when _INTL("Retirar Apoyo en Combate")
            if pbConfirmMessage(_INTL("Heizo: ¿Deseas que retire mi apoyo en combate por ahora?"))
              $game_variables[992] = 0
              pbDeregisterPartner rescue nil
              pbMessage(_INTL("Heizo: Como quieras. Me limitaré a observar."))
            end
            $game_map.autoplay; return
          when _INTL("Cambiar Ropa")
            # Salta al bloque de Ropa abajo
          when _INTL("Vuelve al Centro Pokémon")
            # Salta al bloque de Quedarse abajo
          when _INTL("Nada por ahora")
            $game_map.autoplay; return
          end
        else
          # --- LÓGICA MENÚ ESTÁTICO ---
          if cmd == 0 # REPETIR COMBATE
             # Mantener lógica original de combate
          elsif cmd == 1 # MERCADO NEGRO
             # Salta abajo
          elsif cmd == 2 # ACOMPAÑAME
             # Salta abajo
          else
             $game_map.autoplay; return
          end
        end

        # REDIRECCIÓN DEL MENÚ SEGURA (ROBUSTA POR ETIQUETA)
        choice_text = main_choices[cmd]
        
        if choice_text == _INTL("Mercado Negro") || cmd == 1 # Soporte de tienda
          # Lógica Mercado Negro (Sistema de Categorías)
          $game_temp.mart_prices = {}
          _heizo_open_shop = lambda do |syms, half_price_all, special_prices|
            items = []
            syms.each do |sym|
              item_id = getID(PBItems, sym) rescue nil
              next if !item_id || item_id <= 0
              next if pbIsImportantItem?(item_id) && $PokemonBag.pbQuantity(item_id) > 0
              items.push(item_id)
              base = (pbGetPrice(item_id) rescue 200).to_i
              base = 200 if base <= 0
              price = special_prices[sym] || (half_price_all ? [(base / 2).to_i, 10].max : base)
              $game_temp.mart_prices[item_id] = [price, -1]
            end
            if !items.empty?
              scene = PokemonMartScene.new; screen = PokemonMartScreen.new(scene, items); screen.pbBuyScreen
            end
          end

          loop do
            pbBGMPlay("Acertijos")
            cat = Kernel.pbHeizoShopCategoryMenu
            break if cat == 6
            case cat
            when 0 # BALLS
              _heizo_open_shop.call([:POKEBALL, :GREATBALL, :ULTRABALL, :NETBALL, :DIVEBALL, :NESTBALL, :REPEATBALL, :TIMERBALL, :LUXURYBALL, :DUSKBALL, :HEALBALL, :QUICKBALL, :FASTBALL, :LEVELBALL, :LUREBALL, :HEAVYBALL, :LOVEBALL, :FRIENDBALL, :MOONBALL, :POKEBALLCASERA, :SUPERBALLCASERA, :ULTRABALLCASERA, :MASTERBALL], true, { :MASTERBALL => 50000 })
            when 1 # CURA
              _heizo_open_shop.call([:POTION, :SUPERPOTION, :HYPERPOTION, :MAXPOTION, :FULLRESTORE, :REVIVE, :MAXREVIVE, :FULLHEAL, :ETHER, :MAXETHER, :ELIXIR, :MAXELIXIR, :ANTIDOTE, :BURNHEAL, :PARLYZHEAL, :ICEHEAL, :AWAKENING, :SITRUSBERRY, :ORANBERRY, :LUMBERRY, :LEPPABERRY, :CHESTOBERRY, :PECHABERRY, :RAWSTBERRY, :ASPEARBERRY, :CHERIBERRY, :PERSIMBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY, :LIECHIBERRY, :GANLONBERRY, :SALACBERRY, :PETAYABERRY, :APICOTBERRY, :CUSTAPBERRY, :LANSATBERRY, :STARFBERRY, :MICLEBERRY, :ENIGMABERRY], true, {})
            when 2 # MATS
              _heizo_open_shop.call([:REPEL, :SUPERREPEL, :MAXREPEL, :FIRESTONE, :WATERSTONE, :THUNDERSTONE, :LEAFSTONE, :MOONSTONE, :SUNSTONE, :DUSKSTONE, :DAWNSTONE, :SHINYSTONE, :EVERSTONE, :DRAGONSCALE, :FRASCOCRISTALINO, :MADERA, :GUIJARRO, :TROZODEHIERRO, :POLVODEHUESO, :ESPECIASEXOTICAS, :POLVOEXPLOSIVO, :HPUP, :PROTEIN, :IRON, :CALCIUM, :ZINC, :CARBOS, :PPUP, :PPMAX, :LUCKYEGG, :EXPSHARE, :AMULETCOIN, :SHINYZADOR], true, { :SHINYZADOR => 5000 })
            when 3 # COMBATE
              _heizo_open_shop.call([:LEFTOVERS, :BLACKSLUDGE, :SHELLBELL, :BIGROOT, :LIFEORB, :EXPERTBELT, :MUSCLEBAND, :WISEGLASSES, :CHOICEBAND, :CHOICESPECS, :CHOICESCARF, :FOCUSSASH, :FOCUSBAND, :WHITEHERB, :POWERHERB, :MENTALHERB, :AIRBALLOON, :ROCKYHELMET, :EJECTBUTTON, :REDCARD, :EVIOLITE, :QUICKCLAW, :RAZORCLAW, :SCOPELENS, :WIDELENS, :ZOOMLENS, :BRIGHTPOWDER, :HEATROCK, :DAMPROCK, :SMOOTHROCK, :ICYROCK, :LIGHTCLAY, :FLAMEORB, :TOXICORB, :DESTINYKNOT, :KINGSROCK, :RAZORFANG, :METRONOME, :GRIPCLAW, :BINDINGBAND, :FLOATSTONE, :ABSORBBULB, :CELLBATTERY, :SHEDSHELL, :SMOKEBALL, :IRONBALL, :RINGTARGET, :LAGGINGTAIL], true, {})
            when 4 # TIPOS
              _heizo_open_shop.call([:FLAMEPLATE, :SPLASHPLATE, :ZAPPLATE, :MEADOWPLATE, :ICICLEPLATE, :FISTPLATE, :TOXICPLATE, :EARTHPLATE, :SKYPLATE, :MINDPLATE, :INSECTPLATE, :STONEPLATE, :SPOOKYPLATE, :DRACOPLATE, :DREADPLATE, :IRONPLATE, :CHARCOAL, :MYSTICWATER, :MAGNET, :MIRACLESEED, :NEVERMELTICE, :BLACKBELT, :POISONBARB, :SOFTSAND, :SHARPBEAK, :TWISTEDSPOON, :SILVERPOWDER, :HARDSTONE, :SPELLTAG, :DRAGONFANG, :BLACKGLASSES, :METALCOAT, :SILKSCARF, :FIREGEM, :WATERGEM, :ELECTRICGEM, :GRASSGEM, :ICEGEM, :FIGHTINGGEM, :POISONGEM, :GROUNDGEM, :FLYINGGEM, :PSYCHICGEM, :BUGGEM, :ROCKGEM, :GHOSTGEM, :DRAGONGEM, :DARKGEM, :STEELGEM, :NORMALGEM, :SEAINCENSE, :WAVEINCENSE, :ROSEINCENSE, :ODDINCENSE, :ROCKINCENSE, :LAXINCENSE, :FULLINCENSE], true, {})
            when 5 # ROPA
              pbHeizoClanClothesV2 rescue nil
            end
          end
          $game_map.autoplay; return

        elsif choice_text == _INTL("Cambiar Ropa")
          pbHeizoClanClothesV2 rescue nil
          $game_map.autoplay; return

        elsif choice_text == _INTL("Vuelve al Centro Pokémon") || choice_text == _INTL("Acompáñame") || (cmd == 2 && !$heizo_following)
          # Lógica Despedida/Seguimiento
          if pbHeizoFollowing?
            pbMessage(_INTL("Heizo: Bien. Volveré a por más hidromiel. Cuídate."))
            pbStopHeizoFollowing rescue nil
            pbWait(10); spawn_heizo_final rescue nil
          else
            pbMessage(_INTL("Heizo: Bien. Vamos a ver de qué pasta estás hecho."))
            pbStartHeizoFollowing rescue nil
          end
          $game_map.autoplay; return
        end

        if cmd == 0 && !$heizo_following # REPETIR COMBATE
          pbMessage(_INTL("Heizo: Así me gusta. Vamos."))
          
          # Elegir Modo de Combate (Menú de Selección)
          cmd_mode = pbMessage(_INTL("Heizo: ¿Cómo quieres luchar esta vez?"), [
            _INTL("Individual"),
            _INTL("Doble")
          ], 0)
          is_double = (cmd_mode == 1)

          if is_double
            # Comprobación de seguridad
            player_healthy = $Trainer.party.count { |p| p && p.hp > 0 && !p.isEgg? }
            if player_healthy < 2
              pbMessage(_INTL("Heizo: Tipo, es imposible que me ganes así... no perdamos el tiempo."))
              pbMessage(_INTL("Heizo: Vuelve cuando tengas al menos dos Pokémon en condiciones."))
              $game_map.autoplay; return
            end
          end

          # --- REPETICIÓN DE CINEMÁTICA Y COMBATE ---
          if heizo_event
            pbMoveRoute($game_player, [
              PBMoveRoute::ChangeSpeed, 2, 
              PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right
            ])
            pbMoveRoute(heizo_event, [
              PBMoveRoute::ChangeSpeed, 2, 
              PBMoveRoute::Wait, 32,
              PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right, PBMoveRoute::Right
            ], true) 
          end
          pbWait(40) 

          # Fundido y TP
          black_vp = Viewport.new(0,0,Graphics.width,Graphics.height); black_vp.z = 999999
          col = Color.new(0,0,0,0)
          for j in 0..17; col.set(0,0,0,j*15); black_vp.color = col; Graphics.update; Input.update; end

          $game_player.instance_variable_set(:@through, false); $game_player.instance_variable_set(:@move_route_forcing, false)
          heizo_event.instance_variable_set(:@through, false); heizo_event.instance_variable_set(:@move_route_forcing, false) if heizo_event
          
          p_pos = $game_variables[997]; h_pos = $game_variables[998]
          $game_player.moveto(p_pos[0], p_pos[1]); $game_player.instance_variable_set(:@direction, p_pos[2])
          if heizo_event; heizo_event.moveto(h_pos[0], h_pos[1]); heizo_event.instance_variable_set(:@direction, h_pos[2]); end
          $game_map.need_refresh = true; $game_player.straighten

          # Preparar Batalla
          max_level = $Trainer.party.map { |p| p.level }.max || 5
          heizo_opponent = PokeBattle_Trainer.new("Heizo", 35)
          heizo_opponent.party = pbGetHeizoTeam(max_level)
          bgm = "CombateLider" # MÚSICA DE COMBATE LÍDER
          $PokemonGlobal.nextBattleBack = "Pantano"
          
          decision = 0
          pbBattleAnimation(bgm) { 
            black_vp.dispose
            scene = pbNewBattleScene
            # USAR LA ETIQUETA HEIZO BATTLE PARA LOS DIÁLOGOS
            battle = HeizoBattle.new(scene, $Trainer.party, heizo_opponent.party, $Trainer, heizo_opponent)
            battle.doublebattle = is_double
            battle.instance_variable_set(:@heizo_battle, true) # ETIQUETA ROBUSTA
            battle.instance_variable_set(:@endspeech, "¿Cómo ha podido ser esto...? Mi equipo magnífico ha sido derrotado. Me has dejado sin palabras... por ahora.") # FIX CAJA VACIA
            battle.internalbattle = true; pbPrepareBattle(battle); pbSceneStandby { decision = battle.pbStartBattle }
          }
          
          # Resultado
          if decision == 1
            pbMessage(_INTL("Heizo: Otra vez derrotado. Bien jugado."))
          else
            pbMessage(_INTL("Heizo: He ganado. Vuelve cuando quieras la revancha."))
            pbStartOver
          end
          # Volver a la mesa
          if heizo_event && h_pos; heizo_event.moveto(h_pos[0], h_pos[1]); heizo_event.instance_variable_set(:@direction, h_pos[2]); end
          return
          
        elsif cmd == 1 # MERCADO NEGRO - Sistema de Categorías
          # Inicializar precios globales compartidos entre categorías
          $game_temp.mart_prices = {}

          # Helper lambda: construye stock y abre la pantalla de COMPRA directamente
          _heizo_open_shop = lambda do |syms, half_price_all, special_prices|
            items = []
            syms.each do |sym|
              item_id = getID(PBItems, sym) rescue nil
              next if !item_id || item_id <= 0
              next if pbIsImportantItem?(item_id) && $PokemonBag.pbQuantity(item_id) > 0
              items.push(item_id)
              base = (pbGetPrice(item_id) rescue 200).to_i
              base = 200 if base <= 0
              if special_prices.key?(sym)
                price = special_prices[sym]
              elsif half_price_all
                price = [(base / 2).to_i, 10].max
              else
                price = base
              end
              $game_temp.mart_prices[item_id] = [price, -1]
            end
            if !items.empty?
              scene = PokemonMartScene.new
              screen = PokemonMartScreen.new(scene, items)
              screen.pbBuyScreen
            end
          end

          if $heizo_following
            pbMessage(_INTL("Heizo: Ya que te sigo, puedo soltar algo de mi bolsa... pero no esperes regalos. ¿Qué buscas?"))
          else
            pbMessage(_INTL("Heizo: Todo a mitad de precio. Elige una sección... o lárgate."))
          end
          # --- BUCLE DE CATEGORÍAS ---
          loop do
            pbBGMPlay("Acertijos")
            cat = Kernel.pbHeizoShopCategoryMenu # NUEVO MENÚ CON ICONOS
            
            break if cat == 6 # Salir

            case cat
            # -------------------------------------------------------
            when 0 # POKÉ BALLS
              _heizo_open_shop.call([
                :POKEBALL, :GREATBALL, :ULTRABALL,
                :NETBALL, :DIVEBALL, :NESTBALL, :REPEATBALL, :TIMERBALL,
                :LUXURYBALL, :DUSKBALL, :HEALBALL, :QUICKBALL,
                :FASTBALL, :LEVELBALL, :LUREBALL, :HEAVYBALL,
                :LOVEBALL, :FRIENDBALL, :MOONBALL,
                :POKEBALLCASERA, :SUPERBALLCASERA, :ULTRABALLCASERA,
                :MASTERBALL
              ], true, { :MASTERBALL => 50000 })

            # -------------------------------------------------------
            when 1 # BAYAS Y CURACIÓN
              _heizo_open_shop.call([
                # Pociones y Revivir
                :POTION, :SUPERPOTION, :HYPERPOTION, :MAXPOTION, :FULLRESTORE,
                :REVIVE, :MAXREVIVE, :FULLHEAL,
                # Éteres y Elixires
                :ETHER, :MAXETHER, :ELIXIR, :MAXELIXIR,
                # Curaciones de estado
                :ANTIDOTE, :BURNHEAL, :PARLYZHEAL, :ICEHEAL, :AWAKENING,
                # Bayas de curación y estado
                :SITRUSBERRY, :ORANBERRY, :LUMBERRY, :LEPPABERRY,
                :CHESTOBERRY, :PECHABERRY, :RAWSTBERRY, :ASPEARBERRY, :CHERIBERRY,
                :PERSIMBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY,
                # Bayas de stat boost
                :LIECHIBERRY, :GANLONBERRY, :SALACBERRY, :PETAYABERRY, :APICOTBERRY,
                :CUSTAPBERRY, :LANSATBERRY, :STARFBERRY, :MICLEBERRY, :ENIGMABERRY
              ], true, {})

            # -------------------------------------------------------
            when 2 # MATERIALES, VITAMINAS Y EVOLUCIÓN
              _heizo_open_shop.call([
                # Repelentes y Mapas
                :REPEL, :SUPERREPEL, :MAXREPEL,
                # Piedras evolutivas
                :FIRESTONE, :WATERSTONE, :THUNDERSTONE, :LEAFSTONE,
                :MOONSTONE, :SUNSTONE, :DUSKSTONE, :DAWNSTONE, :SHINYSTONE,
                :EVERSTONE, :DRAGONSCALE,
                # Materiales de crafteo
                :FRASCOCRISTALINO, :MADERA, :GUIJARRO, :TROZODEHIERRO,
                :POLVODEHUESO, :ESPECIASEXOTICAS, :POLVOEXPLOSIVO,
                # Vitaminas
                :HPUP, :PROTEIN, :IRON, :CALCIUM, :ZINC, :CARBOS,
                :PPUP, :PPMAX,
                # Utilidad
                :LUCKYEGG, :EXPSHARE, :AMULETCOIN,
                :SHINYZADOR
              ], true, { :SHINYZADOR => 5000 })

            # -------------------------------------------------------
            when 3 # OBJETOS DE COMBATE
              _heizo_open_shop.call([
                :LEFTOVERS, :BLACKSLUDGE, :SHELLBELL, :BIGROOT,
                :LIFEORB, :EXPERTBELT, :MUSCLEBAND, :WISEGLASSES,
                :CHOICEBAND, :CHOICESPECS, :CHOICESCARF,
                :FOCUSSASH, :FOCUSBAND, :WHITEHERB, :POWERHERB, :MENTALHERB,
                :AIRBALLOON, :ROCKYHELMET, :EJECTBUTTON, :REDCARD, :EVIOLITE,
                :QUICKCLAW, :RAZORCLAW, :SCOPELENS, :WIDELENS, :ZOOMLENS, :BRIGHTPOWDER,
                :HEATROCK, :DAMPROCK, :SMOOTHROCK, :ICYROCK, :LIGHTCLAY,
                :FLAMEORB, :TOXICORB, :DESTINYKNOT, :KINGSROCK, :RAZORFANG,
                :METRONOME, :GRIPCLAW, :BINDINGBAND, :FLOATSTONE,
                :ABSORBBULB, :CELLBATTERY, :SHEDSHELL, :SMOKEBALL,
                :IRONBALL, :RINGTARGET, :LAGGINGTAIL
              ], true, {})

            # -------------------------------------------------------
            when 4 # POTENCIADORES DE TIPO
              _heizo_open_shop.call([
                # Placas
                :FLAMEPLATE, :SPLASHPLATE, :ZAPPLATE, :MEADOWPLATE, :ICICLEPLATE,
                :FISTPLATE, :TOXICPLATE, :EARTHPLATE, :SKYPLATE, :MINDPLATE,
                :INSECTPLATE, :STONEPLATE, :SPOOKYPLATE, :DRACOPLATE, :DREADPLATE, :IRONPLATE,
                # Objetos de tipo
                :CHARCOAL, :MYSTICWATER, :MAGNET, :MIRACLESEED, :NEVERMELTICE,
                :BLACKBELT, :POISONBARB, :SOFTSAND, :SHARPBEAK, :TWISTEDSPOON,
                :SILVERPOWDER, :HARDSTONE, :SPELLTAG, :DRAGONFANG,
                :BLACKGLASSES, :METALCOAT, :SILKSCARF,
                # Gemas
                :FIREGEM, :WATERGEM, :ELECTRICGEM, :GRASSGEM, :ICEGEM,
                :FIGHTINGGEM, :POISONGEM, :GROUNDGEM, :FLYINGGEM, :PSYCHICGEM,
                :BUGGEM, :ROCKGEM, :GHOSTGEM, :DRAGONGEM, :DARKGEM, :STEELGEM, :NORMALGEM,
                # Inciensos
                :SEAINCENSE, :WAVEINCENSE, :ROSEINCENSE, :ODDINCENSE, :ROCKINCENSE,
                :LAXINCENSE, :FULLINCENSE
              ], true, {})
              
            # -------------------------------------------------------
            when 5 # ROPAJES DEL CLAN CAZADOR
              # --- Helper robusto para cambiar el sprite del jugador en mkxp-z ---
              _heizo_set_player_sprite = lambda do |sprite_name|
                begin
                  $game_player.instance_variable_set(:@character_name, sprite_name)
                  $game_player.instance_variable_set(:@tile_id, 0)
                  $game_player.character_name = sprite_name rescue nil
                  if $scene.is_a?(Scene_Map) && $scene.respond_to?(:spriteset)
                    sp = $scene.spriteset
                    begin
                      arr = sp.instance_variable_get(:@character_sprites) rescue []
                      arr.each do |s|
                        next unless s.respond_to?(:update)
                        ch = s.instance_variable_get(:@character) rescue nil
                        if ch == $game_player
                          s.instance_variable_set(:@character_name, nil) rescue nil
                          s.instance_variable_set(:@tile_id, nil) rescue nil
                          s.update rescue nil
                          break
                        end
                      end
                    rescue; end
                  end
                  $game_map.need_refresh = true rescue nil
                  Graphics.update rescue nil
                rescue => e
                  $game_player.character_name = sprite_name rescue nil
                end
              end

              if $game_variables[994] == 1
                # --- DEVOLVER ROPAJES ---
                pbMessage(_INTL("Heizo: Devolviendo los ropajes del clan."))
                if pbConfirmMessage(_INTL("¿Devolver los ropajes del clan cazador?"))
                  original_sprite = $game_variables[993].to_s
                  if original_sprite != "" && original_sprite != "cazadorow"
                    restore_sprite = original_sprite
                  else
                    begin
                      restore_sprite = ($Trainer.female ? "girl_walk" : "boy_walk")
                    rescue
                      restore_sprite = "boy_walk"
                    end
                  end
                  _heizo_set_player_sprite.call(restore_sprite)
                  $game_variables[994] = 0
                  $game_variables[993] = ""
                  pbSEPlay("PRSFX- Shadow Claw2") rescue nil
                  pbMessage(_INTL("Heizo: Bien. Vuelven donde deben estar."))
                  pbMessage(_INTL("Heizo: Cuídate en la ruta. Sin la marca del clan, estás a merced del tiempo."))
                else
                  pbMessage(_INTL("Heizo: Sigue llevándolos. Son tuyos mientras los honres."))
                end
              else
                # --- COMPRAR ROPAJES ---
                pbMessage(_INTL("Heizo: ¿Los ropajes del clan?"))
                pbMessage(_INTL("Heizo: No son exactamente los míos. Son del clan de cazadores al que pertenezco."))
                pbMessage(_INTL("Heizo: Cuero curtido en frío. Resistentes al viento, a la lluvia y a las inclemencias de cualquier ruta."))
                pbMessage(_INTL("Heizo: Los llevamos en expedición. Para la aventura, no para el salón."))
                pbMessage(_INTL("Heizo: 100$. Y no porque necesite el dinero."))

                if pbConfirmMessage(_INTL("¿Comprar los ropajes del clan cazador por 100$?"))
                  if $Trainer.money >= 100
                    $Trainer.money -= 100
                    current_sprite = $game_player.character_name.to_s
                    current_sprite = "boy_walk" if current_sprite == "" || current_sprite == "cazadorow"
                    $game_variables[993] = current_sprite
                    _heizo_set_player_sprite.call("cazadorow")
                    $game_variables[994] = 1
                    Kernel.pbUpdateVehicle rescue nil
                    pbSEPlay("PRSFX- Shadow Claw2") rescue nil
                    pbMessage(_INTL("Heizo: Tómalos."))
                    pbMessage(_INTL("Heizo: Ahora llevas la marca del clan. Cada ruta te lo agradecerá."))
                  else
                    pbMessage(_INTL("Heizo: No tienes suficiente."))
                    pbMessage(_INTL("Heizo: 100$. El clan no regala sus ropajes."))
                  end
                else
                  pbMessage(_INTL("Heizo: Como quieras. No son para todo el mundo."))
                end
              end
            end # case cat
          end # loop categorías

          $game_temp.mart_prices = nil
          if $heizo_following
            pbMessage(_INTL("Heizo: Negocio cerrado. Sigamos."))
          else
            pbMessage(_INTL("Heizo: Buen provecho. Ya sabes dónde encontrarme."))
          end
          $game_map.autoplay; return

        elsif cmd == 2 # ACOMPAÑAR / QUEDARSE
          if $heizo_following
            pbSEPlay("VozCrisantoSigh") rescue nil
            pbMessage(_INTL("Heizo: Está bien. Nos vemos en el Centro Pokémon."))
            
            # Desactivar mercenario al irse
            $game_variables[992] = 0
            pbDeregisterPartner rescue nil
            
            # --- INICIAR CORTINA NEGRA ANTES DEL TP ---
            blink_vp = Viewport.new(0,0,Graphics.width,Graphics.height); blink_vp.z = 999999
            blink_col = Color.new(0,0,0,0)
            for j in 0..12 # Aumentamos un poco más la duración del fundido de entrada
              blink_col.set(0,0,0,j*22)
              blink_vp.color = blink_col
              Graphics.update
              Input.update
            end
            
            # EL MOMENTO DEL TP (con la pantalla totalmente negra)
            pbRemoveDependency2("HeizoNPC") rescue nil
            
            # Re-activar el evento si estamos en el mapa base
            if $game_map.events[995]
              ge = $game_map.events[995]
              ge.instance_variable_set(:@erased, false)
              ge.refresh rescue nil
              h_pos = $game_variables[998] || [3, 11, 2]
              ge.moveto(h_pos[0], h_pos[1])
              ge.instance_variable_set(:@direction, h_pos[2])
              $game_player.straighten rescue nil
            else
              $heizo_spawned = false
            end
            
            # Un pequeño parpadeo extra en negro puro para asegurar
            pbWait(5) if defined?(pbWait)
            
            # Fundido de salida
            for j in 0..12
              blink_col.set(0,0,0,255 - j*22)
              blink_vp.color = blink_col
              Graphics.update
              Input.update
            end
            blink_vp.dispose
            # ------------------------------------------
            
            $game_map.autoplay; return
          else
            pbMessage(_INTL("Heizo: ¿Quieres mi compañía? Bien."))
            pbMessage(_INTL("Heizo: Me mantendré al margen en tus combates, pero seguiré vendiéndote mercancía."))
            begin
              pbAddDependency2(995, "HeizoNPC", nil)
            rescue => e
              pbMessage(_INTL("Heizo: Mmm... parece que no puedo seguirte en las condiciones actuales."))
            end
            $game_map.autoplay; return
          end
          
        elsif cmd == 3 # NADA POR AHORA
          pbMessage(_INTL("Heizo: Estaré aquí conteniendo el aliento. Sin prisa."))
          $game_map.autoplay; return
        end
    end
  end
end

# ==============================================================================
# --- SISTEMA DE LEYENDAS Y EQUIPO DE HEIZO ---
# ==============================================================================

# Añadir atributo de leyenda a los Pokémon
class PokeBattle_Pokemon
  attr_accessor :heizo_legend
end

# Evaluación de IA mejorada para Heizo (Óptimo)
def pbHeizoCalculateLeadScore(pkmn, opponent)
  return -999 if !pkmn || !opponent || pkmn.hp <= 0
  score = 0
  
  # 1. ANALISIS OFENSIVO (¡Priorizar 4x agresivamente!)
  for move in pkmn.moves
    next if !move || move.id == 0
    # Calcular eficacia contra tipos del rival
    eff = PBTypes.getCombinedEffectiveness(move.type, opponent.type1, opponent.type2) rescue 8
    
    if eff > 12 # Súper efectivo (x2 o x4)
      score += (eff == 32) ? 200 : 80 # Multiplicador bestial para 4x (ej: Planta vs Quagsire)
      score += 30 if pkmn.hasType?(move.type) # Bonus STAB
    elsif eff < 8 && eff > 0 # Resistido
      score -= 30
    elsif eff == 0 # Inmune
      score -= 100
    end
  end

  # 2. ANALISIS DEFENSIVO (Resistencias e Inmunidades)
  # ¿Es Heizo inmune a los tipos del rival? (ej: Corviknight vs Tierra)
  [opponent.type1, opponent.type2].each do |t|
    next if t.nil? || t < 0
    res = PBTypes.getCombinedEffectiveness(t, pkmn.type1, pkmn.type2) rescue 8
    if res == 0;      score += 60 # Inmunidad (Muy útil para leads defensivos como Corviknight)
    elsif res < 8;    score += 25 # Resistencia
    elsif res > 12;   score -= 50 # Debilidad crítica (Peligro)
    end
  end

  # 3. Factor de Nivel y Salud
  score += pkmn.level * 2
  score += (pkmn.hp * 50 / pkmn.totalhp).to_i if pkmn.totalhp > 0
  
  return score
end

# Helper para cambiar ropa (limpio)
def pbHeizoClanClothesV2
  ropajes_label = ($game_variables[994] == 1) ? _INTL("Devolver ropajes") : _INTL("Ropajes del Clan")
  # (Lógica original de ropa simplificada para el menú)
  if $game_variables[994] == 1
    # Devolver
    original = $game_variables[993].to_s
    original = ($Trainer.female ? "girl_walk" : "boy_walk") if original == "" || original == "cazadorow"
    $game_player.character_name = original
    $game_variables[994] = 0
    pbMessage(_INTL("Heizo: Vuelto a la normalidad."))
  else
    # Poner
    $game_variables[993] = $game_player.character_name
    $game_player.character_name = "cazadorow"
    $game_variables[994] = 1
    pbMessage(_INTL("Heizo: Bienvenido al clan."))
  end
end

def pbGetHeizoTeam(max_level)
  team = []
  fire_type = getID(PBTypes, :FIRE) rescue 2
  dragon_type = getID(PBTypes, :DRAGON) rescue 16

  # 1. Corviknight
  cor = PokeBattle_Pokemon.new(:CORVIKNIGHT, max_level, $Trainer)
  cor.setNature(getID(PBNatures,:IMPISH)); cor.iv = [31,31,31,31,31,31]; cor.ev = [252, 4, 252, 0, 0, 0]
  cor.setItem(:LEFTOVERS); cor.setAbility(getID(PBAbilities,:MIRRORARMOR))
  c_mov = [:ROOST, :IRONDEFENSE, :BRAVEBIRD, :IRONHEAD, :UTURN, :DEFOG, :TAUNT, :DRILLPECK]
  c_mov.each_with_index { |m, idx| cor.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }; cor.calcStats
  cor.heizo_legend = "Forjado en las cenizas del Gran Colapso; el único veterano que no huyó cuando las sombras devoraron la ciudad."
  team.push(cor)

  # 2. Swampert (Mega Visual / Stats Base)
  swa = PokeBattle_Pokemon.new(:SWAMPERT, max_level, $Trainer)
  swa.setNature(getID(PBNatures,:ADAMANT)); swa.iv = [31,31,31,31,31,31]; swa.ev = [252, 252, 4, 0, 0, 0]
  swa.setItem(:EXPERTBELT); swa.setAbility(getID(PBAbilities,:INTIMIDATE))
  s_mov = [:WATERFALL, :EARTHQUAKE, :ICEPUNCH, :STONEEDGE, :SUPERPOWER, :BRICKBREAK, :YAWN, :STEALTHROCK]
  s_mov.each_with_index { |m, idx| swa.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }
  swa.form = 1 # MEGA VISUAL
  swa.instance_variable_set(:@form_sprite_only_final, true)
  swa.calcStats # Recalculate to enforce base stats
  swa.heizo_legend = "Titán de las marismas tóxicas que Heizo rescató. Su fuerza es tan vasta que no necesita despertar su poder para vencer."
  team.push(swa)

  # 3. Venusaur
  ven = PokeBattle_Pokemon.new(:VENUSAUR, max_level, $Trainer)
  ven.setNature(getID(PBNatures,:CALM)); ven.iv = [31,31,31,31,31,31]; ven.ev = [252, 0, 0, 0, 4, 252]
  ven.setItem(:BIGROOT); ven.setAbility(getID(PBAbilities,:POISONPOINT))
  v_mov = [:GIGADRAIN, :SLUDGEBOMB, :LEECHSEED, :SPORE, :SYNTHESIS, :SOLARBEAM, :TOXIC, :VENOSHOCK]
  v_mov.each_with_index { |m, idx| ven.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }; ven.calcStats
  ven.heizo_legend = "Surgió de la primera semilla tras la devastación. Heizo lo crió entre ruinas, convirtiéndolo en guardián de lo que queda."
  team.push(ven)
  # 4. Charizard (Shiny / Mega-Y Visual / Stats Base / Fuego-Dragón + Dragon Boost)
  cha = PokeBattle_Pokemon.new(:CHARIZARD, max_level, $Trainer)
  cha.makeShiny
  cha.setNature(getID(PBNatures,:RASH)); cha.iv = [31,31,31,31,31,31]; cha.ev = [0, 252, 0, 252, 0, 6]
  cha.setItem(:DRAGONFANG); cha.setAbility(getID(PBAbilities,:ADAPTABILITY))
  cha_mov = [:FIREFANG, :FLAMETHROWER, :DRAGONCLAW, :DRAGONPULSE, :ROOST, :CRUNCH, :DRAGONDANCE, :AIRSLASH]
  cha_mov.each_with_index { |m, idx| cha.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }
  
  cha.form = 2 # MEGA Y VISUAL (Stats Base)
  cha.instance_variable_set(:@form_sprite_only_final, true)
  cha.calcStats # Recalculate to enforce base stats
  
  # Forzar tipo Fuego/Dragón
  cha.instance_variable_set(:@type1, fire_type); cha.instance_variable_set(:@type2, dragon_type)
  cha.instance_variable_set(:@custom_type1, fire_type); cha.instance_variable_set(:@custom_type2, dragon_type)
  cha.heizo_legend = "Descendió de cielos rojos cuando el mundo ardió. Heizo lo domó compartiendo su fuego e hidromiel bajo una lluvia de ceniza."
  team.push(cha)

  # 5. Gengar
  gen = PokeBattle_Pokemon.new(:GENGAR, max_level, $Trainer)
  gen.setNature(getID(PBNatures,:TIMID)); gen.iv = [31,31,31,31,31,31]; gen.ev = [4, 0, 0, 252, 252, 0]
  gen.setItem(:AIRBALLOON); gen.setAbility(getID(PBAbilities,:PRANKSTER))
  g_mov = [:SHADOWBALL, :SLUDGEBOMB, :DESTINYBOND, :DARKPULSE, :HYPNOSIS, :DREAMEATER, :TOXIC, :NIGHTMARE]
  g_mov.each_with_index { |m, idx| gen.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }; gen.calcStats
  gen.heizo_legend = "Sombra huérfana del Eclipse Eterno. Ahora flota sobre un globo de helio, canalizando bromas pesadas de la ultratumba para sumir a sus rivales en un sueño eterno."
  team.push(gen)

  # 6. Zeraora
  zer = PokeBattle_Pokemon.new(:ZERAORA, max_level, $Trainer)
  zer.setNature(getID(PBNatures,:JOLLY)); zer.iv = [31,31,31,31,31,31]; zer.ev = [4, 252, 0, 252, 0, 0]
  zer.setItem(:SHELLBELL); zer.setAbility(getID(PBAbilities,:SERENEGRACE))
  z_mov = [:THUNDERPUNCH, :SPARK, :WILDCHARGE, :VOLTSWITCH, :CLOSECOMBAT, :DRAINPUNCH, :BLAZEKICK, :FAKEOUT]
  z_mov.each_with_index { |m, idx| zer.moves[idx] = PBMove.new(getID(PBMoves, m)) rescue nil }; zer.calcStats
  zer.heizo_legend = "El rayo errante de la Montaña Blanca. No es un siervo, es un aliado unido a Heizo por una promesa inquebrantable."
  team.push(zer)

  return team
end

# Parche para mostrar las Leyendas en el Resumen
def pbApplyHeizoSummaryPatch
  return if !defined?(PokemonSummaryScene)
  return if PokemonSummaryScene.method_defined?(:drawPageTwo_heizo_legend)
  
  PokemonSummaryScene.class_eval do
    alias drawPageTwo_heizo_legend drawPageTwo
    def drawPageTwo(pokemon)
      drawPageTwo_heizo_legend(pokemon)
      return if !pokemon.respond_to?(:heizo_legend) || !pokemon.heizo_legend
      
      overlay = @sprites["overlay"].bitmap
      # Limpiar el área de notas de entrenador para que el texto épico de Heizo no se superponga
      overlay.clear_rect(232, 74, 280, 260) rescue nil
      
      # Escribir la leyenda
      epic_text = "<c3=F83820,E09890>Origen:\n<c3=404040,B0B0B0>" + pokemon.heizo_legend
      drawFormattedTextEx(overlay, 232, 78, 276, epic_text)
    end
  end
end

# ==============================================================================
# --- CAJA DE REFERENCIA DE HEIZO (PC CAJA 30) ---
# ==============================================================================

# Parche robusto para la interfaz del PC (Bloquea mover, pero permite ver ataques/datos)
def pbApplyHeizoPC_Lockdown
  return if !defined?(PokemonStorageScreen)
  return if PokemonStorageScreen.method_defined?(:pbStartScreen_heizo_lock)
  
  begin
    Object.const_get(:PokemonStorageScreen).class_eval do
      # 1. Gancho de inicio
      alias pbStartScreen_heizo_lock pbStartScreen
      def pbStartScreen(command)
        pbSetupHeizoReferenceBox(@storage)
        pbStartScreen_heizo_lock(command)
      end

      # 2. Bloqueo de Retirada (Modificado: Consultar datos en lugar de solo bloquear)
      alias pbWithdraw_heizo_lock pbWithdraw
      def pbWithdraw(selected, heldpoke)
        if selected && selected[0] == 29
          pokemon = @storage[selected[0], selected[1]]
          pbSummary(selected, nil) if pokemon
          return false
        end
        pbWithdraw_heizo_lock(selected, heldpoke)
      end

      # 3. Bloqueo de Mover (Modificado: Abrir Datos en lugar de error al hacer clic)
      alias pbHold_heizo_lock pbHold
      def pbHold(selected)
        if selected && selected[0] == 29
          pokemon = @storage[selected[0], selected[1]]
          pbSummary(selected, nil) if pokemon
          return
        end
        pbHold_heizo_lock(selected)
      end

      # 4. Bloqueo de Intercambio
      alias pbSwap_heizo_lock pbSwap
      def pbSwap(selected)
        if selected && selected[0] == 29
          pbDisplay(_INTL("Heizo: Solo para referencia. No puedes mover mis Pokémon."))
          return false
        end
        pbSwap_heizo_lock(selected)
      end

      # 5. Bloqueo de Depósito
      alias pbPlace_heizo_lock pbPlace
      def pbPlace(selected)
        if selected && selected[0] == 29
          pbDisplay(_INTL("Heizo: Caja bloqueada. No puedes dejar Pokémon aquí."))
          return
        end
        pbPlace_heizo_lock(selected)
      end

      # 3. Menú contextual optimizado (Datos visibles para ver ataques)
      alias pbShowCommands_heizo_lock pbShowCommands
      def pbShowCommands(msg, commands)
        if @storage && @storage.currentBox == 29
          new_cmds = []
          # Permitirmos "Datos", variantes de "Salir/Cerrar", y comandos de la Caja (Saltar, Paisaje, Nombre)
          allowed = ["datos", "summary", "información", "informacion", "salir", "cancel", "cerrar", "saltar", "paisaje", "nombre"]
          for c in commands
            clean_c = c.gsub(/<.*?>/, "").strip rescue c
            new_cmds << c if allowed.any? { |a| clean_c.downcase.include?(a) }
          end
          return pbShowCommands_heizo_lock(msg, new_cmds.empty? ? commands : new_cmds)
        end
        pbShowCommands_heizo_lock(msg, commands)
      end

      # 7. Hook de Datos (Mostrar resumen directamente)
      alias pbSummary_heizo_lock pbSummary
      def pbSummary(selected, pokemon)
        pbSummary_heizo_lock(selected, pokemon)
      end
    end
  rescue => e
    pbPrint("Error en Heizo PC Patch: #{e.message}") if $DEBUG
  end
end

# Generador del equipo en la Caja 30
def pbSetupHeizoReferenceBox(storage)
  return if !storage
  pbApplyHeizoPC_Lockdown
  pbApplyHeizoSummaryPatch
  
  box_index = 29 
  # Set default name and background only if it hasn't been customized yet
  if storage[box_index].name == "Caja 30" || storage[box_index].name == "Box 30" || storage[box_index].name == ""
    storage[box_index].name = "EQUIPO HEIZO"
    storage[box_index].background = "box17"
  end
  # Si ya tenía el nombre puesto pero el fondo sigue siendo el por defecto (box5), lo forzamos a Alma una vez.
  if storage[box_index].name == "EQUIPO HEIZO" && storage[box_index].background == "box5"
    storage[box_index].background = "box17"
  end
  
  max_level = PBExperience::MAXLEVEL
  
  heizo_party = pbGetHeizoTeam(max_level)
  heizo_party.each_with_index do |pkmn, i|
    storage[box_index, i] = pkmn
  end
end

# ===============================================================================
# INTERFAZ GRÁFICA DEL MERCADO NEGRO DE HEIZO
# ===============================================================================

module Kernel
  def self.pbHeizoShopCategoryMenu
    # DEFINICIÓN DINÁMICA: Evita NameError al arrancar el juego
    # (Window_CommandPokemon no existe hasta que cargan los scripts base)
    if !defined?(Window_HeizoShopCategory)
      cls = Class.new(Window_CommandPokemon) do
        def initialize(commands, x, y)
          @icons = [
            "Graphics/Icons/item275", # Poke Ball
            "Graphics/Icons/item217", # Poción
            "Graphics/Icons/item033", # Piedra Fuego (Materiales)
            "Graphics/Icons/item212", # Choice Band (Combate)
            "Graphics/Icons/item245", # Tabla Llama (Tipo)
            "Graphics/Icons/item513", # Ropajes (Mochila)
            nil                       # Salir
          ]
          super(commands, 330)
          self.x = x
          self.y = y
          self.z = 99999
        end

        def drawItem(index, count, rect)
          icon_path = @icons[index]
          if icon_path
            begin
              bmp_path = pbBitmapName(icon_path)
              if bmp_path
                bitmap_full = AnimatedBitmap.new(bmp_path)
                bitmap = bitmap_full.bitmap
                dest_rect = Rect.new(rect.x + 8, rect.y + (rect.height - 24) / 2, 24, 24)
                src_rect = Rect.new(0, 0, bitmap.width, bitmap.height)
                self.contents.stretch_blt(dest_rect, bitmap, src_rect)
                bitmap_full.dispose
              end
            rescue
            end
          end
          text_rect = Rect.new(rect.x + 44, rect.y, rect.width - 44, rect.height)
          super(index, count, text_rect)
        end
      end
      Object.const_set(:Window_HeizoShopCategory, cls)
    end

    ropajes_label = ($game_variables[994] == 1) ? _INTL("Devolver ropajes") : _INTL("Ropajes del Clan")
    commands = [
      _INTL("Poke Balls"),
      _INTL("Bayas y Curacion"),
      _INTL("Materiales y Evolucion"),
      _INTL("Objetos de Combate"),
      _INTL("Potenciadores de Tipo"),
      ropajes_label,
      _INTL("Salir")
    ]
    
    # Viewport para el fondo oscurecido "Premium"
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99998
    
    # Sombreado de fondo
    bg_sprite = Sprite.new(viewport)
    bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 160))
    
    # Ventana de selección
    w = 330
    h = commands.length * 32 + 32
    x = (Graphics.width - w) / 2
    y = (Graphics.height - h) / 2
    
    window = Window_HeizoShopCategory.new(commands, x, y)
    window.viewport = viewport
    
    # Animación rápida de entrada
    window.opacity = 0
    window.contents_opacity = 0
    for i in 0..6
      window.opacity += 40
      window.contents_opacity += 40
      Graphics.update
    end
    
    pbSEPlay("GUI menu open")
    
    result = -1
    loop do
      Graphics.update
      Input.update
      window.update
      
      if Input.trigger?(Input::B)
        pbSEPlay("GUI menu close")
        result = 6 # Salir
        break
      end
      
      if Input.trigger?(Input::C)
        pbSEPlay("GUI menu selection")
        result = window.index
        break
      end
    end
    
    # Limpieza
    window.dispose
    bg_sprite.bitmap.dispose
    bg_sprite.dispose
    viewport.dispose
    
    return result
  end
end





