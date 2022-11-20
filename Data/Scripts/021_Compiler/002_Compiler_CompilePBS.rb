module Compiler
  module_function

  def compile_PBS_file_generic(game_data, path)
    compile_pbs_file_message_start(path)
    game_data::DATA.clear
    # Read from PBS file
    File.open(path, "rb") { |f|
      FileLineData.file = path   # For error reporting
      # Read a whole section's lines at once, then run through this code.
      # contents is a hash containing all the XXX=YYY lines in that section, where
      # the keys are the XXX and the values are the YYY (as unprocessed strings).
      schema = game_data.schema
      idx = 0
      pbEachFileSection(f, schema) { |contents, section_name|
        echo "." if idx % 50 == 0
        Graphics.update if idx % 250 == 0
        idx += 1
        data_hash = {:id => section_name.to_sym}
        # Go through schema hash of compilable data and compile this section
        schema.each_key do |key|
          FileLineData.setSection(section_name, key, contents[key])   # For error reporting
          if key == "SectionName"
            data_hash[schema[key][0]] = pbGetCsvRecord(section_name, key, schema[key])
            next
          end
          # Skip empty properties
          next if contents[key].nil?
          # Compile value for key
          if schema[key][1][0] == "^"
            contents[key].each do |val|
              value = pbGetCsvRecord(val, key, schema[key])
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] ||= []
              data_hash[schema[key][0]].push(value)
            end
            data_hash[schema[key][0]].compact!
          else
            value = pbGetCsvRecord(contents[key], key, schema[key])
            value = nil if value.is_a?(Array) && value.empty?
            data_hash[schema[key][0]] = value
          end
        end
        # Validate and modify the compiled data
        yield false, data_hash if block_given?
        if game_data.exists?(data_hash[:id])
          raise _INTL("Section name '{1}' is used twice.\r\n{2}", data_hash[:id], FileLineData.linereport)
        end
        # Add section's data to records
        game_data.register(data_hash)
      }
    }
    yield true, nil if block_given?
    # Save all data
    game_data.save
    process_pbs_file_message_end
  end

  #=============================================================================
  # Compile Town Map data
  #=============================================================================
  def compile_town_map(path = "PBS/town_map.txt")
    compile_pbs_file_message_start(path)
    sections = []
    # Read from PBS file
    File.open(path, "rb") { |f|
      FileLineData.file = path   # For error reporting
      # Read a whole section's lines at once, then run through this code.
      # contents is a hash containing all the XXX=YYY lines in that section, where
      # the keys are the XXX and the values are the YYY (as unprocessed strings).
      schema = {
        "SectionName" => [:id,        "u"],
        "Name"        => [:real_name, "s"],
        "Filename"    => [:filename,  "s"],
        "Point"       => [:point,     "^uussUUUU"]
      }
      idx = 0
      pbEachFileSection(f, schema) { |contents, section_name|
        echo "." if idx % 50 == 0
        Graphics.update if idx % 250 == 0
        idx += 1
        data_hash = {:id => section_name.to_sym}
        # Go through schema hash of compilable data and compile this section
        schema.each_key do |key|
          FileLineData.setSection(section_name, key, contents[key])   # For error reporting
          if key == "SectionName"
            data_hash[schema[key][0]] = pbGetCsvRecord(section_name, key, schema[key])
            next
          end
          # Skip empty properties
          next if contents[key].nil?
          # Compile value for key
          if schema[key][1][0] == "^"
            contents[key].each do |val|
              value = pbGetCsvRecord(val, key, schema[key])
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] ||= []
              data_hash[schema[key][0]].push(value)
            end
            data_hash[schema[key][0]].compact!
          else
            value = pbGetCsvRecord(contents[key], key, schema[key])
            value = nil if value.is_a?(Array) && value.empty?
            data_hash[schema[key][0]] = value
          end
        end
        # Validate and modify the compiled data
        validate_compiled_town_map(data_hash)
        if sections[data_hash[:id]]
          raise _INTL("Region ID '{1}' is used twice.\r\n{2}", data_hash[:id], FileLineData.linereport)
        end
        # Add town map messages to records
        sections[data_hash[:id]] = [data_hash[:real_name], data_hash[:filename], data_hash[:point]]
      }
    }
    validate_all_compiled_town_maps(sections)
    # Save all data
    save_data(sections, "Data/town_map.dat")
    process_pbs_file_message_end
  end

  def validate_compiled_town_map(hash)
  end

  def validate_all_compiled_town_maps(sections)
    # Get town map names and descriptions for translating
    region_names = []
    point_names = []
    interest_names = []
    sections.each_with_index do |region, i|
      region_names[i] = region[0]
      region[2].each do |point|
        point_names.push(point[2])
        interest_names.push(point[3])
      end
    end
    MessageTypes.setMessages(MessageTypes::RegionNames, region_names)
    MessageTypes.setMessagesAsHash(MessageTypes::PlaceNames, point_names)
    MessageTypes.setMessagesAsHash(MessageTypes::PlaceDescriptions, interest_names)
  end

  #=============================================================================
  # Compile map connections
  #=============================================================================
  def compile_connections(path = "PBS/map_connections.txt")
    compile_pbs_file_message_start(path)
    records   = []
    pbCompilerEachPreppedLine(path) { |line, lineno|
      hashenum = {
        "N" => "N", "North" => "N",
        "E" => "E", "East"  => "E",
        "S" => "S", "South" => "S",
        "W" => "W", "West"  => "W"
      }
      record = []
      thisline = line.dup
      record.push(csvInt!(thisline, lineno))
      record.push(csvEnumFieldOrInt!(thisline, hashenum, "", sprintf("(line %d)", lineno)))
      record.push(csvInt!(thisline, lineno))
      record.push(csvInt!(thisline, lineno))
      record.push(csvEnumFieldOrInt!(thisline, hashenum, "", sprintf("(line %d)", lineno)))
      record.push(csvInt!(thisline, lineno))
      if !pbRgssExists?(sprintf("Data/Map%03d.rxdata", record[0]))
        print _INTL("Warning: Map {1}, as mentioned in the map connection data, was not found.\r\n{2}", record[0], FileLineData.linereport)
      end
      if !pbRgssExists?(sprintf("Data/Map%03d.rxdata", record[3]))
        print _INTL("Warning: Map {1}, as mentioned in the map connection data, was not found.\r\n{2}", record[3], FileLineData.linereport)
      end
      case record[1]
      when "N"
        raise _INTL("North side of first map must connect with south side of second map\r\n{1}", FileLineData.linereport) if record[4] != "S"
      when "S"
        raise _INTL("South side of first map must connect with north side of second map\r\n{1}", FileLineData.linereport) if record[4] != "N"
      when "E"
        raise _INTL("East side of first map must connect with west side of second map\r\n{1}", FileLineData.linereport) if record[4] != "W"
      when "W"
        raise _INTL("West side of first map must connect with east side of second map\r\n{1}", FileLineData.linereport) if record[4] != "E"
      end
      records.push(record)
    }
    save_data(records, "Data/map_connections.dat")
    process_pbs_file_message_end
  end

  #=============================================================================
  # Compile phone messages
  #=============================================================================
  def compile_phone(path = "PBS/phone.txt")
    compile_PBS_file_generic(GameData::PhoneMessage, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_phone_contacts : validate_compiled_phone_contact(hash)
    end
  end

  def validate_compiled_phone_contact(hash)
    # Split trainer type/name/version into their own values, generate compound ID from them
    if hash[:id].strip.downcase == "default"
      hash[:id] = "default"
      hash[:trainer_type] = hash[:id]
    else
      line_data = pbGetCsvRecord(hash[:id], -1, [0, "esU", :TrainerType])
      hash[:trainer_type] = line_data[0]
      hash[:real_name] = line_data[1]
      hash[:version] = line_data[2] || 0
      hash[:id] = [hash[:trainer_type], hash[:real_name], hash[:version]]
    end
  end

  def validate_all_compiled_phone_contacts
    # Get all phone messages for translating
    messages = []
    GameData::PhoneMessage.each do |contact|
      [:intro, :intro_morning, :intro_afternoon, :intro_evening, :body, :body1,
       :body2, :battle_request, :battle_remind, :end].each do |msg_type|
        msgs = contact.send(msg_type)
        next if !msgs || msgs.length == 0
        msgs.each { |msg| messages.push(msg) }
      end
    end
    MessageTypes.setMessagesAsHash(MessageTypes::PhoneMessages, messages)
  end

  #=============================================================================
  # Compile type data
  #=============================================================================
  def compile_types(path = "PBS/types.txt")
    compile_PBS_file_generic(GameData::Type, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_types : validate_compiled_type(hash)
    end
  end

  def validate_compiled_type(hash)
    # Remove duplicate weaknesses/resistances/immunities
    hash[:weaknesses].uniq! if hash[:weaknesses].is_a?(Array)
    hash[:resistances].uniq! if hash[:resistances].is_a?(Array)
    hash[:immunities].uniq! if hash[:immunities].is_a?(Array)
  end

  def validate_all_compiled_types
    type_names = []
    GameData::Type.each do |type|
      # Ensure all weaknesses/resistances/immunities are valid types
      type.weaknesses.each do |other_type|
        next if GameData::Type.exists?(other_type)
        raise _INTL("'{1}' is not a defined type ({2}, section {3}, Weaknesses).", other_type.to_s, path, type.id)
      end
      type.resistances.each do |other_type|
        next if GameData::Type.exists?(other_type)
        raise _INTL("'{1}' is not a defined type ({2}, section {3}, Resistances).", other_type.to_s, path, type.id)
      end
      type.immunities.each do |other_type|
        next if GameData::Type.exists?(other_type)
        raise _INTL("'{1}' is not a defined type ({2}, section {3}, Immunities).", other_type.to_s, path, type.id)
      end
      # Get type names for translating
      type_names.push(type.real_name)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::Types, type_names)
  end

  #=============================================================================
  # Compile ability data
  #=============================================================================
  def compile_abilities(path = "PBS/abilities.txt")
    compile_PBS_file_generic(GameData::Ability, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_abilities : validate_compiled_ability(hash)
    end
  end

  def validate_compiled_ability(hash)
  end

  def validate_all_compiled_abilities
    # Get abilty names/descriptions for translating
    ability_names = []
    ability_descriptions = []
    GameData::Ability.each do |ability|
      ability_names.push(ability.real_name)
      ability_descriptions.push(ability.real_description)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::Abilities, ability_names)
    MessageTypes.setMessagesAsHash(MessageTypes::AbilityDescs, ability_descriptions)
  end

  #=============================================================================
  # Compile move data
  #=============================================================================
  def compile_moves(path = "PBS/moves.txt")
    compile_PBS_file_generic(GameData::Move, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_moves : validate_compiled_move(hash)
    end
  end

  def validate_compiled_move(hash)
    if (hash[:category] || 2) == 2 && (hash[:base_damage] || 0) != 0
      raise _INTL("Move {1} is defined as a Status move with a non-zero base damage.\r\n{2}",
                  hash[:name], FileLineData.linereport)
    elsif (hash[:category] || 2) != 2 && (hash[:base_damage] || 0) == 0
      print _INTL("Warning: Move {1} is defined as Physical or Special but has a base damage of 0. Changing it to a Status move.\r\n{2}",
                  hash[:name], FileLineData.linereport)
      hash[:category] = 2
    end
  end

  def validate_all_compiled_moves
    # Get move names/descriptions for translating
    move_names = []
    move_descriptions = []
    GameData::Move.each do |move|
      move_names.push(move.real_name)
      move_descriptions.push(move.real_description)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::Moves, move_names)
    MessageTypes.setMessagesAsHash(MessageTypes::MoveDescriptions, move_descriptions)
  end

  #=============================================================================
  # Compile item data
  #=============================================================================
  def compile_items(path = "PBS/items.txt")
    compile_PBS_file_generic(GameData::Item, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_items : validate_compiled_item(hash)
    end
  end

  def validate_compiled_item(hash)
  end

  def validate_all_compiled_items
    # Get item names/descriptions for translating
    item_names = []
    item_names_plural = []
    item_descriptions = []
    GameData::Item.each do |item|
      item_names.push(item.real_name)
      item_names_plural.push(item.real_name_plural)
      item_descriptions.push(item.real_description)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::Items, item_names)
    MessageTypes.setMessagesAsHash(MessageTypes::ItemPlurals, item_names_plural)
    MessageTypes.setMessagesAsHash(MessageTypes::ItemDescriptions, item_descriptions)
  end

  #=============================================================================
  # Compile berry plant data
  #=============================================================================
  def compile_berry_plants(path = "PBS/berry_plants.txt")
    compile_PBS_file_generic(GameData::BerryPlant, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_berry_plants : validate_compiled_berry_plant(hash)
    end
  end

  def validate_compiled_berry_plant(hash)
  end

  def validate_all_compiled_berry_plants
  end

  #=============================================================================
  # Compile Pokémon data
  #=============================================================================
  def compile_pokemon(path = "PBS/pokemon.txt")
    compile_PBS_file_generic(GameData::Species, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_pokemon : validate_compiled_pokemon(hash)
    end
  end

  # NOTE: This method is also called by def validate_compiled_pokemon_form
  #       below, and since a form's hash can contain very little data, don't
  #       assume any data exists.
  def validate_compiled_pokemon(hash)
    # Convert base stats array to a hash
    if hash[:base_stats].is_a?(Array)
      new_stats = {}
      GameData::Stat.each_main do |s|
        new_stats[s.id] = (hash[:base_stats][s.pbs_order] || 1) if s.pbs_order >= 0
      end
      hash[:base_stats] = new_stats
    end
    # Convert EVs array to a hash
    if hash[:evs].is_a?(Array)
      new_evs = {}
      hash[:evs].each { |val| new_evs[val[0]] = val[1] }
      GameData::Stat.each_main { |s| new_evs[s.id] ||= 0 }
      hash[:evs] = new_evs
    end
    # Convert height and weight to integer values of tenths of a unit
    hash[:height] = [(hash[:height] * 10).round, 1].max if hash[:height]
    hash[:weight] = [(hash[:weight] * 10).round, 1].max if hash[:weight]
    # Record all evolutions as not being prevolutions
    if hash[:evolutions].is_a?(Array)
      hash[:evolutions].each { |evo| evo[3] = false }
    end
    # Remove duplicate types
    hash[:types].uniq! if hash[:types].is_a?(Array)
  end

  def validate_all_compiled_pokemon
    # Enumerate all offspring species (this couldn't be done earlier)
    GameData::Species.each do |species|
      FileLineData.setSection(species.id.to_s, "Offspring", nil)   # For error reporting
      offspring = species.offspring
      offspring.each_with_index do |sp, i|
        offspring[i] = csvEnumField!(sp, :Species, "Offspring", species.id)
      end
    end
    # Enumerate all evolution species and parameters (this couldn't be done earlier)
    GameData::Species.each do |species|
      FileLineData.setSection(species.id.to_s, "Evolutions", nil)   # For error reporting
      species.evolutions.each do |evo|
        evo[0] = csvEnumField!(evo[0], :Species, "Evolutions", species.id)
        param_type = GameData::Evolution.get(evo[1]).parameter
        if param_type.nil?
          evo[2] = nil
        elsif param_type == Integer
          evo[2] = csvPosInt!(evo[2])
        elsif param_type != String
          evo[2] = csvEnumField!(evo[2], param_type, "Evolutions", species.id)
        end
      end
    end
    # Add prevolution "evolution" entry for all evolved species
    all_evos = {}
    GameData::Species.each do |species|   # Build a hash of prevolutions for each species
      species.evolutions.each do |evo|
        all_evos[evo[0]] = [species.species, evo[1], evo[2], true] if !all_evos[evo[0]]
      end
    end
    GameData::Species.each do |species|   # Distribute prevolutions
      species.evolutions.push(all_evos[species.species].clone) if all_evos[species.species]
    end
    # Get species names/descriptions for translating
    species_names = []
    species_form_names = []
    species_categories = []
    species_pokedex_entries = []
    GameData::Species.each do |species|
      species_names.push(species.real_name)
      species_form_names.push(species.real_form_name)
      species_categories.push(species.real_category)
      species_pokedex_entries.push(species.real_pokedex_entry)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::Species, species_names)
    MessageTypes.setMessagesAsHash(MessageTypes::FormNames, species_form_names)
    MessageTypes.setMessagesAsHash(MessageTypes::Kinds, species_categories)
    MessageTypes.setMessagesAsHash(MessageTypes::Entries, species_pokedex_entries)
  end

  #=============================================================================
  # Compile Pokémon forms data
  # NOTE: Doesn't use compile_PBS_file_generic because it needs its own schema
  #       and shouldn't clear GameData::Species at the start.
  #=============================================================================
  def compile_pokemon_forms(path = "PBS/pokemon_forms.txt")
    compile_pbs_file_message_start(path)
    # Read from PBS file
    File.open(path, "rb") { |f|
      FileLineData.file = path   # For error reporting
      # Read a whole section's lines at once, then run through this code.
      # contents is a hash containing all the XXX=YYY lines in that section, where
      # the keys are the XXX and the values are the YYY (as unprocessed strings).
      schema = GameData::Species.schema(true)
      idx = 0
      pbEachFileSection(f, schema) { |contents, section_name|
        echo "." if idx % 50 == 0
        Graphics.update if idx % 250 == 0
        idx += 1
        data_hash = {:id => section_name.to_sym}
        # Go through schema hash of compilable data and compile this section
        schema.each_key do |key|
          FileLineData.setSection(section_name, key, contents[key])   # For error reporting
          if key == "SectionName"
            data_hash[schema[key][0]] = pbGetCsvRecord(section_name, key, schema[key])
            next
          end
          # Skip empty properties
          next if contents[key].nil?
          # Compile value for key
          if schema[key][1][0] == "^"
            contents[key].each do |val|
              value = pbGetCsvRecord(val, key, schema[key])
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] ||= []
              data_hash[schema[key][0]].push(value)
            end
            data_hash[schema[key][0]].compact!
          else
            value = pbGetCsvRecord(contents[key], key, schema[key])
            value = nil if value.is_a?(Array) && value.empty?
            data_hash[schema[key][0]] = value
          end
        end
        # Validate and modify the compiled data
        validate_compiled_pokemon_form(data_hash)
        if GameData::Species.exists?(data_hash[:id])
          raise _INTL("Section name '{1}' is used twice.\r\n{2}", data_hash[:id], FileLineData.linereport)
        end
        # Add section's data to records
        GameData::Species.register(data_hash)
      }
    }
    validate_all_compiled_pokemon_forms
    # Save all data
    GameData::Species.save
    process_pbs_file_message_end
  end

  def validate_compiled_pokemon_form(hash)
    # Split species and form into their own values, generate compound ID from them
    hash[:species] = hash[:id][0]
    hash[:form] = hash[:id][1]
    hash[:id] = sprintf("%s_%d", hash[:species].to_s, hash[:form]).to_sym
    if !GameData::Species.exists?(hash[:species])
      raise _INTL("Undefined species ID '{1}'.\r\n{3}", hash[:species], FileLineData.linereport)
    elsif GameData::Species.exists?(hash[:id])
      raise _INTL("Form {1} for species ID {2} is defined twice.\r\n{3}", hash[:form], hash[:species], FileLineData.linereport)
    end
    # Perform the same validations on this form as for a regular species
    validate_compiled_pokemon(hash)
    # Inherit undefined properties from base species
    base_data = GameData::Species.get(hash[:species])
    [:real_name, :real_category, :real_pokedex_entry, :base_exp, :growth_rate,
     :gender_ratio, :catch_rate, :happiness, :hatch_steps, :incense, :height,
     :weight, :color, :shape, :habitat, :generation].each do |property|
      hash[property] = base_data.send(property) if hash[property].nil?
    end
    [:types, :base_stats, :evs, :tutor_moves, :egg_moves, :abilities,
     :hidden_abilities, :egg_groups, :offspring, :flags].each do |property|
      hash[property] = base_data.send(property).clone if hash[property].nil?
    end
    if !hash[:moves].is_a?(Array) || hash[:moves].length == 0
      hash[:moves] ||= []
      base_data.moves.each { |m| hash[:moves].push(m.clone) }
    end
    if !hash[:evolutions].is_a?(Array) || hash[:evolutions].length == 0
      hash[:evolutions] ||= []
      base_data.evolutions.each { |e| hash[:evolutions].push(e.clone) }
    end
    if hash[:wild_item_common].nil? && hash[:wild_item_uncommon].nil? &&
       hash[:wild_item_rare].nil?
      hash[:wild_item_common] = base_data.wild_item_common.clone
      hash[:wild_item_uncommon] = base_data.wild_item_uncommon.clone
      hash[:wild_item_rare] = base_data.wild_item_rare.clone
    end
  end

  def validate_all_compiled_pokemon_forms
    # Add prevolution "evolution" entry for all evolved species
    all_evos = {}
    GameData::Species.each do |species|   # Build a hash of prevolutions for each species
      species.evolutions.each do |evo|
        all_evos[evo[0]] = [species.species, evo[1], evo[2], true] if !evo[3] && !all_evos[evo[0]]
      end
    end
    GameData::Species.each do |species|   # Distribute prevolutions
      next if species.evolutions.any? { |evo| evo[3] }   # Already has prevo listed
      next if !all_evos[species.species]
      # Record what species evolves from
      species.evolutions.push(all_evos[species.species].clone)
      # Record that the prevolution can evolve into species
      prevo = GameData::Species.get(all_evos[species.species][0])
      if prevo.evolutions.none? { |evo| !evo[3] && evo[0] == species.species }
        prevo.evolutions.push([species.species, :None, nil])
      end
    end
    # Get species names/descriptions for translating
    species_form_names = []
    species_categories = []
    species_pokedex_entries = []
    GameData::Species.each do |species|
      next if species.form == 0
      species_form_names.push(species.real_form_name)
      species_categories.push(species.real_category)
      species_pokedex_entries.push(species.real_pokedex_entry)
    end
    MessageTypes.addMessagesAsHash(MessageTypes::FormNames, species_form_names)
    MessageTypes.addMessagesAsHash(MessageTypes::Kinds, species_categories)
    MessageTypes.addMessagesAsHash(MessageTypes::Entries, species_pokedex_entries)
  end

  #=============================================================================
  # Compile Pokémon metrics data
  #=============================================================================
  def compile_pokemon_metrics(path = "PBS/pokemon_metrics.txt")
    compile_PBS_file_generic(GameData::SpeciesMetrics, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_pokemon_metrics : validate_compiled_pokemon_metrics(hash)
    end
  end

  def validate_compiled_pokemon_metrics(hash)
    # Split species and form into their own values, generate compound ID from them
    if hash[:id].is_a?(Array)
      hash[:species] = hash[:id][0]
      hash[:form] = hash[:id][1] || 0
      if hash[:form] == 0
        hash[:id] = hash[:species]
      else
        hash[:id] = sprintf("%s_%d", hash[:species].to_s, hash[:form]).to_sym
      end
    end
  end

  def validate_all_compiled_pokemon_metrics
  end

  #=============================================================================
  # Compile Shadow Pokémon data
  #=============================================================================
  def compile_shadow_pokemon(path = "PBS/shadow_pokemon.txt")
    compile_PBS_file_generic(GameData::ShadowPokemon, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_shadow_pokemon : validate_compiled_shadow_pokemon(hash)
    end
  end

  def validate_compiled_shadow_pokemon(hash)
  end

  def validate_all_compiled_shadow_pokemon
  end

  #=============================================================================
  # Compile Regional Dexes
  #=============================================================================
  def compile_regional_dexes(path = "PBS/regional_dexes.txt")
    compile_pbs_file_message_start(path)
    dex_lists = []
    section = nil
    pbCompilerEachPreppedLine(path) { |line, line_no|
      Graphics.update if line_no % 200 == 0
      if line[/^\s*\[\s*(\d+)\s*\]\s*$/]
        section = $~[1].to_i
        if dex_lists[section]
          raise _INTL("Dex list number {1} is defined at least twice.\r\n{2}", section, FileLineData.linereport)
        end
        dex_lists[section] = []
      else
        raise _INTL("Expected a section at the beginning of the file.\r\n{1}", FileLineData.linereport) if !section
        species_list = line.split(",")
        species_list.each do |species|
          next if !species || species.empty?
          s = parseSpecies(species)
          dex_lists[section].push(s)
        end
      end
    }
    # Check for duplicate species in a Regional Dex
    dex_lists.each_with_index do |list, index|
      unique_list = list.uniq
      next if list == unique_list
      list.each_with_index do |s, i|
        next if unique_list[i] == s
        raise _INTL("Dex list number {1} has species {2} listed twice.\r\n{3}", index, s, FileLineData.linereport)
      end
    end
    # Save all data
    save_data(dex_lists, "Data/regional_dexes.dat")
    process_pbs_file_message_end
  end

  #=============================================================================
  # Compile ribbon data
  #=============================================================================
  def compile_ribbons(path = "PBS/ribbons.txt")
    compile_PBS_file_generic(GameData::Ribbon, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_ribbons : validate_compiled_ribbon(hash)
    end
  end

  def validate_compiled_ribbon(hash)
  end

  def validate_all_compiled_ribbons
    # Get ribbon names/descriptions for translating
    ribbon_names = []
    ribbon_descriptions = []
    GameData::Ribbon.each do |ribbon|
      ribbon_names.push(ribbon.real_name)
      ribbon_descriptions.push(ribbon.real_description)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::RibbonNames, ribbon_names)
    MessageTypes.setMessagesAsHash(MessageTypes::RibbonDescriptions, ribbon_descriptions)
  end

  #=============================================================================
  # Compile wild encounter data
  #=============================================================================
  def compile_encounters(path = "PBS/encounters.txt")
    compile_pbs_file_message_start(path)
    GameData::Encounter::DATA.clear
    encounter_hash = nil
    step_chances   = nil
    current_type   = nil
    max_level = GameData::GrowthRate.max_level
    idx = 0
    pbCompilerEachPreppedLine(path) { |line, line_no|
      echo "." if idx % 50 == 0
      idx += 1
      Graphics.update if idx % 250 == 0
      next if line.length == 0
      if current_type && line[/^\d+,/]   # Species line
        values = line.split(",").collect! { |v| v.strip }
        if !values || values.length < 3
          raise _INTL("Expected a species entry line for encounter type {1} for map '{2}', got \"{3}\" instead.\r\n{4}",
                      GameData::EncounterType.get(current_type).real_name, encounter_hash[:map], line, FileLineData.linereport)
        end
        values = pbGetCsvRecord(line, line_no, [0, "vevV", nil, :Species])
        values[3] = values[2] if !values[3]
        if values[2] > max_level
          raise _INTL("Level number {1} is not valid (max. {2}).\r\n{3}", values[2], max_level, FileLineData.linereport)
        elsif values[3] > max_level
          raise _INTL("Level number {1} is not valid (max. {2}).\r\n{3}", values[3], max_level, FileLineData.linereport)
        elsif values[2] > values[3]
          raise _INTL("Minimum level is greater than maximum level: {1}\r\n{2}", line, FileLineData.linereport)
        end
        encounter_hash[:types][current_type].push(values)
      elsif line[/^\[\s*(.+)\s*\]$/]   # Map ID line
        values = $~[1].split(",").collect! { |v| v.strip.to_i }
        values[1] = 0 if !values[1]
        map_number = values[0]
        map_version = values[1]
        # Add map encounter's data to records
        if encounter_hash
          encounter_hash[:types].each_value do |slots|
            next if !slots || slots.length == 0
            slots.each_with_index do |slot, i|
              next if !slot
              slots.each_with_index do |other_slot, j|
                next if i == j || !other_slot
                next if slot[1] != other_slot[1] || slot[2] != other_slot[2] || slot[3] != other_slot[3]
                slot[0] += other_slot[0]
                slots[j] = nil
              end
            end
            slots.compact!
            slots.sort! { |a, b| (a[0] == b[0]) ? a[1].to_s <=> b[1].to_s : b[0] <=> a[0] }
          end
          GameData::Encounter.register(encounter_hash)
        end
        # Raise an error if a map/version combo is used twice
        key = sprintf("%s_%d", map_number, map_version).to_sym
        if GameData::Encounter::DATA[key]
          raise _INTL("Encounters for map '{1}' are defined twice.\r\n{2}", map_number, FileLineData.linereport)
        end
        step_chances = {}
        # Construct encounter hash
        encounter_hash = {
          :id           => key,
          :map          => map_number,
          :version      => map_version,
          :step_chances => step_chances,
          :types        => {}
        }
        current_type = nil
      elsif !encounter_hash   # File began with something other than a map ID line
        raise _INTL("Expected a map number, got \"{1}\" instead.\r\n{2}", line, FileLineData.linereport)
      else
        # Check if line is an encounter method name or not
        values = line.split(",").collect! { |v| v.strip }
        current_type = (values[0] && !values[0].empty?) ? values[0].to_sym : nil
        if current_type && GameData::EncounterType.exists?(current_type)   # Start of a new encounter method
          step_chances[current_type] = values[1].to_i if values[1] && !values[1].empty?
          step_chances[current_type] ||= GameData::EncounterType.get(current_type).trigger_chance
          encounter_hash[:types][current_type] = []
        else
          raise _INTL("Undefined encounter type \"{1}\" for map '{2}'.\r\n{3}",
                      line, encounter_hash[:map], FileLineData.linereport)
        end
      end
    }
    # Add last map's encounter data to records
    if encounter_hash
      encounter_hash[:types].each_value do |slots|
        next if !slots || slots.length == 0
        slots.each_with_index do |slot, i|
          next if !slot
          slots.each_with_index do |other_slot, j|
            next if i == j || !other_slot
            next if slot[1] != other_slot[1] || slot[2] != other_slot[2] || slot[3] != other_slot[3]
            slot[0] += other_slot[0]
            slots[j] = nil
          end
        end
        slots.compact!
        slots.sort! { |a, b| (a[0] == b[0]) ? a[1].to_s <=> b[1].to_s : b[0] <=> a[0] }
      end
      GameData::Encounter.register(encounter_hash)
    end
    # Save all data
    GameData::Encounter.save
    process_pbs_file_message_end
  end

  #=============================================================================
  # Compile trainer type data
  #=============================================================================
  def compile_trainer_types(path = "PBS/trainer_types.txt")
    compile_PBS_file_generic(GameData::TrainerType, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_trainer_types : validate_compiled_trainer_type(hash)
    end
  end

  def validate_compiled_trainer_type(hash)
  end

  def validate_all_compiled_trainer_types
    # Get trainer type names for translating
    trainer_type_names = []
    GameData::TrainerType.each do |tr_type|
      trainer_type_names.push(tr_type.real_name)
    end
    MessageTypes.setMessagesAsHash(MessageTypes::TrainerTypes, trainer_type_names)
  end

  #=============================================================================
  # Compile individual trainer data
  #=============================================================================
  def compile_trainers(path = "PBS/trainers.txt")
    compile_pbs_file_message_start(path)
    GameData::Trainer::DATA.clear
    schema = GameData::Trainer.schema
    max_level = GameData::GrowthRate.max_level
    trainer_names      = []
    trainer_lose_texts = []
    trainer_hash       = nil
    current_pkmn       = nil
    # Read each line of trainers.txt at a time and compile it as a trainer property
    idx = 0
    pbCompilerEachPreppedLine(path) { |line, line_no|
      echo "." if idx % 50 == 0
      idx += 1
      Graphics.update if idx % 250 == 0
      if line[/^\s*\[\s*(.+)\s*\]\s*$/]
        # New section [trainer_type, name] or [trainer_type, name, version]
        if trainer_hash
          if !current_pkmn
            raise _INTL("Started new trainer while previous trainer has no Pokémon.\r\n{1}", FileLineData.linereport)
          end
          # Add trainer's data to records
          trainer_hash[:id] = [trainer_hash[:trainer_type], trainer_hash[:name], trainer_hash[:version]]
          GameData::Trainer.register(trainer_hash)
        end
        line_data = pbGetCsvRecord($~[1], line_no, [0, "esU", :TrainerType])
        # Construct trainer hash
        trainer_hash = {
          :trainer_type => line_data[0],
          :name         => line_data[1],
          :version      => line_data[2] || 0,
          :pokemon      => []
        }
        current_pkmn = nil
        trainer_names.push(trainer_hash[:name])
      elsif line[/^\s*(\w+)\s*=\s*(.*)$/]
        # XXX=YYY lines
        if !trainer_hash
          raise _INTL("Expected a section at the beginning of the file.\r\n{1}", FileLineData.linereport)
        end
        property_name = $~[1]
        line_schema = schema[property_name]
        next if !line_schema
        property_value = pbGetCsvRecord($~[2], line_no, line_schema)
        # Error checking in XXX=YYY lines
        case property_name
        when "Pokemon"
          if property_value[1] > max_level
            raise _INTL("Bad level: {1} (must be 1-{2}).\r\n{3}", property_value[1], max_level, FileLineData.linereport)
          end
        when "Name"
          if property_value.length > Pokemon::MAX_NAME_SIZE
            raise _INTL("Bad nickname: {1} (must be 1-{2} characters).\r\n{3}", property_value, Pokemon::MAX_NAME_SIZE, FileLineData.linereport)
          end
        when "Moves"
          property_value.uniq!
        when "IV"
          property_value.each do |iv|
            next if iv <= Pokemon::IV_STAT_LIMIT
            raise _INTL("Bad IV: {1} (must be 0-{2}).\r\n{3}", iv, Pokemon::IV_STAT_LIMIT, FileLineData.linereport)
          end
        when "EV"
          property_value.each do |ev|
            next if ev <= Pokemon::EV_STAT_LIMIT
            raise _INTL("Bad EV: {1} (must be 0-{2}).\r\n{3}", ev, Pokemon::EV_STAT_LIMIT, FileLineData.linereport)
          end
          ev_total = 0
          GameData::Stat.each_main do |s|
            next if s.pbs_order < 0
            ev_total += (property_value[s.pbs_order] || property_value[0])
          end
          if ev_total > Pokemon::EV_LIMIT
            raise _INTL("Total EVs are greater than allowed ({1}).\r\n{2}", Pokemon::EV_LIMIT, FileLineData.linereport)
          end
        when "Happiness"
          if property_value > 255
            raise _INTL("Bad happiness: {1} (must be 0-255).\r\n{2}", property_value, FileLineData.linereport)
          end
        when "Ball"
          if !GameData::Item.get(property_value).is_poke_ball?
            raise _INTL("Value {1} isn't a defined Poké Ball.\r\n{2}", property_value, FileLineData.linereport)
          end
        end
        # Record XXX=YYY setting
        case property_name
        when "Items", "LoseText"
          trainer_hash[line_schema[0]] = property_value
          trainer_lose_texts.push(property_value) if property_name == "LoseText"
        when "Pokemon"
          current_pkmn = {
            :species => property_value[0],
            :level   => property_value[1]
          }
          trainer_hash[line_schema[0]].push(current_pkmn)
        else
          if !current_pkmn
            raise _INTL("Pokémon hasn't been defined yet!\r\n{1}", FileLineData.linereport)
          end
          case property_name
          when "IV", "EV"
            value_hash = {}
            GameData::Stat.each_main do |s|
              next if s.pbs_order < 0
              value_hash[s.id] = property_value[s.pbs_order] || property_value[0]
            end
            current_pkmn[line_schema[0]] = value_hash
          else
            current_pkmn[line_schema[0]] = property_value
          end
        end
      end
    }
    # Add last trainer's data to records
    if trainer_hash
      if !current_pkmn
        raise _INTL("End of file reached while last trainer has no Pokémon.\r\n{1}", FileLineData.linereport)
      end
      trainer_hash[:id] = [trainer_hash[:trainer_type], trainer_hash[:name], trainer_hash[:version]]
      GameData::Trainer.register(trainer_hash)
    end
    # Save all data
    GameData::Trainer.save
    MessageTypes.setMessagesAsHash(MessageTypes::TrainerNames, trainer_names)
    MessageTypes.setMessagesAsHash(MessageTypes::TrainerLoseText, trainer_lose_texts)
    process_pbs_file_message_end
  end

  #=============================================================================
  # Compile Battle Tower and other Cups trainers/Pokémon
  #=============================================================================
  def compile_trainer_lists(path = "PBS/battle_facility_lists.txt")
    compile_pbs_file_message_start(path)
    btTrainersRequiredTypes = {
      "Trainers"   => [0, "s"],
      "Pokemon"    => [1, "s"],
      "Challenges" => [2, "*s"]
    }
    if !safeExists?(path)
      File.open(path, "wb") { |f|
        f.write(0xEF.chr)
        f.write(0xBB.chr)
        f.write(0xBF.chr)
        f.write("[DefaultTrainerList]\r\n")
        f.write("Trainers = battle_tower_trainers.txt\r\n")
        f.write("Pokemon = battle_tower_pokemon.txt\r\n")
      }
    end
    sections = []
    MessageTypes.setMessagesAsHash(MessageTypes::BeginSpeech, [])
    MessageTypes.setMessagesAsHash(MessageTypes::EndSpeechWin, [])
    MessageTypes.setMessagesAsHash(MessageTypes::EndSpeechLose, [])
    File.open(path, "rb") { |f|
      FileLineData.file = path
      idx = 0
      pbEachFileSection(f) { |section, name|
        echo "."
        idx += 1
        Graphics.update
        next if name != "DefaultTrainerList" && name != "TrainerList"
        rsection = []
        section.each_key do |key|
          FileLineData.setSection(name, key, section[key])
          schema = btTrainersRequiredTypes[key]
          next if key == "Challenges" && name == "DefaultTrainerList"
          next if !schema
          record = pbGetCsvRecord(section[key], 0, schema)
          rsection[schema[0]] = record
        end
        if !rsection[0]
          raise _INTL("No trainer data file given in section {1}.\r\n{2}", name, FileLineData.linereport)
        end
        if !rsection[1]
          raise _INTL("No trainer data file given in section {1}.\r\n{2}", name, FileLineData.linereport)
        end
        rsection[3] = rsection[0]
        rsection[4] = rsection[1]
        rsection[5] = (name == "DefaultTrainerList")
        if safeExists?("PBS/" + rsection[0])
          rsection[0] = compile_battle_tower_trainers("PBS/" + rsection[0])
        else
          rsection[0] = []
        end
        if safeExists?("PBS/" + rsection[1])
          filename = "PBS/" + rsection[1]
          rsection[1] = []
          pbCompilerEachCommentedLine(filename) { |line, _lineno|
            rsection[1].push(PBPokemon.fromInspected(line))
          }
        else
          rsection[1] = []
        end
        rsection[2] = [] if !rsection[2]
        while rsection[2].include?("")
          rsection[2].delete("")
        end
        rsection[2].compact!
        sections.push(rsection)
      }
    }
    save_data(sections, "Data/trainer_lists.dat")
    process_pbs_file_message_end
  end

  def compile_battle_tower_trainers(filename)
    sections = []
    requiredtypes = {
      "Type"          => [0, "e", :TrainerType],
      "Name"          => [1, "s"],
      "BeginSpeech"   => [2, "s"],
      "EndSpeechWin"  => [3, "s"],
      "EndSpeechLose" => [4, "s"],
      "PokemonNos"    => [5, "*u"]
    }
    trainernames  = []
    beginspeech   = []
    endspeechwin  = []
    endspeechlose = []
    if safeExists?(filename)
      File.open(filename, "rb") { |f|
        FileLineData.file = filename
        pbEachFileSection(f) { |section, name|
          rsection = []
          section.each_key do |key|
            FileLineData.setSection(name, key, section[key])
            schema = requiredtypes[key]
            next if !schema
            record = pbGetCsvRecord(section[key], 0, schema)
            rsection[schema[0]] = record
          end
          trainernames.push(rsection[1])
          beginspeech.push(rsection[2])
          endspeechwin.push(rsection[3])
          endspeechlose.push(rsection[4])
          sections.push(rsection)
        }
      }
    end
    MessageTypes.addMessagesAsHash(MessageTypes::TrainerNames, trainernames)
    MessageTypes.addMessagesAsHash(MessageTypes::BeginSpeech, beginspeech)
    MessageTypes.addMessagesAsHash(MessageTypes::EndSpeechWin, endspeechwin)
    MessageTypes.addMessagesAsHash(MessageTypes::EndSpeechLose, endspeechlose)
    return sections
  end

  #=============================================================================
  # Compile metadata
  # NOTE: Doesn't use compile_PBS_file_generic because it contains data for two
  #       different GameData classes.
  #=============================================================================
  def compile_metadata(path = "PBS/metadata.txt")
    compile_pbs_file_message_start(path)
    GameData::Metadata::DATA.clear
    GameData::PlayerMetadata::DATA.clear
    # Read from PBS file
    File.open(path, "rb") { |f|
      FileLineData.file = path   # For error reporting
      # Read a whole section's lines at once, then run through this code.
      # contents is a hash containing all the XXX=YYY lines in that section, where
      # the keys are the XXX and the values are the YYY (as unprocessed strings).
      global_schema = GameData::Metadata.schema
      player_schema = GameData::PlayerMetadata.schema
      idx = 0
      pbEachFileSection(f) { |contents, section_name|
        echo "." if idx % 50 == 0
        Graphics.update if idx % 250 == 0
        idx += 1
        schema = (section_name.to_i == 0) ? global_schema : player_schema
        data_hash = {:id => section_name.to_sym}
        # Go through schema hash of compilable data and compile this section
        schema.each_key do |key|
          FileLineData.setSection(section_name, key, contents[key])   # For error reporting
          if key == "SectionName"
            data_hash[schema[key][0]] = pbGetCsvRecord(section_name, key, schema[key])
            next
          end
          # Skip empty properties
          next if contents[key].nil?
          # Compile value for key
          if schema[key][1][0] == "^"
            contents[key].each do |val|
              value = pbGetCsvRecord(val, key, schema[key])
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] ||= []
              data_hash[schema[key][0]].push(value)
            end
            data_hash[schema[key][0]].compact!
          else
            value = pbGetCsvRecord(contents[key], key, schema[key])
            value = nil if value.is_a?(Array) && value.empty?
            data_hash[schema[key][0]] = value
          end
        end
        # Validate and modify the compiled data
        if data_hash[:id] == 0
          validate_compiled_global_metadata(data_hash)
          if GameData::Metadata.exists?(data_hash[:id])
            raise _INTL("Global metadata ID '{1}' is used twice.\r\n{2}", data_hash[:id], FileLineData.linereport)
          end
        else
          validate_compiled_player_metadata(data_hash)
          if GameData::PlayerMetadata.exists?(data_hash[:id])
            raise _INTL("Player metadata ID '{1}' is used twice.\r\n{2}", data_hash[:id], FileLineData.linereport)
          end
        end
        # Add section's data to records
        if data_hash[:id] == 0
          GameData::Metadata.register(data_hash)
        else
          GameData::PlayerMetadata.register(data_hash)
        end
      }
    }
    validate_all_compiled_metadata
    # Save all data
    GameData::Metadata.save
    GameData::PlayerMetadata.save
    process_pbs_file_message_end
  end

  def validate_compiled_global_metadata(hash)
    if hash[:home].nil?
      raise _INTL("The entry 'Home' is required in metadata.txt section 0.\r\n{1}", FileLineData.linereport)
    end
  end

  def validate_compiled_player_metadata(hash)
  end

  # Should be used to check both global metadata and player character metadata.
  def validate_all_compiled_metadata
    # Ensure global metadata is defined
    if !GameData::Metadata.exists?(0)
      raise _INTL("Global metadata is not defined in metadata.txt but should be.\r\n{1}", FileLineData.linereport)
    end
    # Ensure player character 1's metadata is defined
    if !GameData::PlayerMetadata.exists?(1)
      raise _INTL("Metadata for player character 1 is not defined in metadata.txt but should be.\r\n{1}", FileLineData.linereport)
    end
    # Get storage creator's name for translating
    storage_creator = [GameData::Metadata.get.real_storage_creator]
    MessageTypes.setMessages(MessageTypes::StorageCreator, storage_creator)
  end

  #=============================================================================
  # Compile map metadata
  #=============================================================================
  def compile_map_metadata(path = "PBS/map_metadata.txt")
    compile_PBS_file_generic(GameData::MapMetadata, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_map_metadata : validate_compiled_map_metadata(hash)
    end
  end

  def validate_compiled_map_metadata(hash)
    # Give the map its RMXP map name if it doesn't define its own
    if nil_or_empty?(hash[:real_name])
      hash[:real_name] = pbLoadMapInfos[id].name
    end
  end

  def validate_all_compiled_map_metadata
    # Get map names for translating
    map_names = []
    GameData::MapMetadata.each { |map| map_names[map.id] = map.real_name }
    MessageTypes.setMessages(MessageTypes::MapNames, map_names)
  end

  #=============================================================================
  # Compile dungeon tileset data
  #=============================================================================
  def compile_dungeon_tilesets(path = "PBS/dungeon_tilesets.txt")
    compile_PBS_file_generic(GameData::DungeonTileset, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_dungeon_tilesets : validate_compiled_dungeon_tileset(hash)
    end
  end

  def validate_compiled_dungeon_tileset(hash)
  end

  def validate_all_compiled_dungeon_tilesets
  end

  #=============================================================================
  # Compile dungeon parameters data
  #=============================================================================
  def compile_dungeon_parameters(path = "PBS/dungeon_parameters.txt")
    compile_PBS_file_generic(GameData::DungeonParameters, path) do |final_validate, hash|
      (final_validate) ? validate_all_compiled_dungeon_parameters : validate_compiled_dungeon_parameters(hash)
    end
  end

  def validate_compiled_dungeon_parameters(hash)
    # Split area and version into their own values, generate compound ID from them
    hash[:area] = hash[:id][0]
    hash[:version] = hash[:id][1] || 0
    if hash[:version] == 0
      hash[:id] = hash[:area]
    else
      hash[:id] = sprintf("%s_%d", hash[:area].to_s, hash[:version]).to_sym
    end
    if GameData::DungeonParameters.exists?(hash[:id])
      raise _INTL("Version {1} of dungeon area {2} is defined twice.\r\n{3}", hash[:version], hash[:area], FileLineData.linereport)
    end
  end

  def validate_all_compiled_dungeon_parameters
  end

  #=============================================================================
  # Compile battle animations
  #=============================================================================
  def compile_animations
    Console.echo_li(_INTL("Compiling animations..."))
    begin
      pbanims = load_data("Data/PkmnAnimations.rxdata")
    rescue
      pbanims = PBAnimations.new
    end
    changed = false
    move2anim = [{}, {}]
=begin
    anims = load_data("Data/Animations.rxdata")
    for anim in anims
      next if !anim || anim.frames.length==1
      found = false
      for i in 0...pbanims.length
        if pbanims[i] && pbanims[i].id==anim.id
          found = true if pbanims[i].array.length>1
          break
        end
      end
      pbanims[anim.id] = pbConvertRPGAnimation(anim) if !found
    end
=end
    pbanims.length.times do |i|
      next if !pbanims[i]
      if pbanims[i].name[/^OppMove\:\s*(.*)$/]
        if GameData::Move.exists?($~[1])
          moveid = GameData::Move.get($~[1]).id
          changed = true if !move2anim[0][moveid] || move2anim[1][moveid] != i
          move2anim[1][moveid] = i
        end
      elsif pbanims[i].name[/^Move\:\s*(.*)$/]
        if GameData::Move.exists?($~[1])
          moveid = GameData::Move.get($~[1]).id
          changed = true if !move2anim[0][moveid] || move2anim[0][moveid] != i
          move2anim[0][moveid] = i
        end
      end
    end
    if changed
      save_data(move2anim, "Data/move2anim.dat")
      save_data(pbanims, "Data/PkmnAnimations.rxdata")
    end
    process_pbs_file_message_end
  end
end
