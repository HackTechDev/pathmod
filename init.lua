-- init.lua
local storage = minetest.get_mod_storage()
local paths = minetest.deserialize(storage:get_string("paths")) or {}
local markers = {}
local following_players = {}
local player_speed = {}
local player_yaw = {} -- yaw actuel des joueurs

-- Sauvegarde
local function save_paths()
    storage:set_string("paths", minetest.serialize(paths))
end

-- Balises
local function clear_markers(pathname)
    if markers[pathname] then
        for _, obj in ipairs(markers[pathname]) do
            if obj and obj:get_luaentity() then obj:remove() end
        end
        markers[pathname] = {}
    end
end

local function create_markers(pathname)
    clear_markers(pathname)
    markers[pathname] = {}
    local path = paths[pathname]
    if not path then return end
    for _, point in ipairs(path) do
        local obj = minetest.add_entity(point, "pathmod:marker")
        if obj then table.insert(markers[pathname], obj) end
    end
end

-- Entité balise
minetest.register_entity("pathmod:marker", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        visual = "cube",
        visual_size = {x=0.5, y=0.5},
        textures = {
            "path_marker.png", "path_marker.png",
            "path_marker.png", "path_marker.png",
            "path_marker.png", "path_marker.png"
        },
        glow = 10,
        pointable = false
    },
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        pos.y = pos.y + math.sin(minetest.get_gametime() * 2) * 0.005
        self.object:set_pos(pos)
    end
})

-- Commande : vitesse
minetest.register_chatcommand("pathspeed", {
    params = "<vitesse>",
    description = "Définit la vitesse (m/s)",
    func = function(name, param)
        local val = tonumber(param)
        if not val or val <= 0 then
            return false, "Usage: /pathspeed <vitesse>"
        end
        player_speed[name] = val
        return true, "Vitesse définie à " .. val .. " m/s."
    end
})

-- Commandes de gestion de chemin
minetest.register_chatcommand("pathnew", {
    params = "<nom>",
    func = function(name, param)
        if param == "" then return false, "Usage: /pathnew <nom>" end
        paths[param] = {}
        save_paths()
        clear_markers(param)
        return true, "Chemin '" .. param .. "' créé."
    end
})

minetest.register_chatcommand("pathadd", {
    params = "<nom>",
    func = function(name, param)
        if not paths[param] then return false, "Chemin inexistant." end
        local player = minetest.get_player_by_name(name)
        if player then
            local pos = vector.round(player:get_pos())
            table.insert(paths[param], pos)
            save_paths()
            create_markers(param)
            return true, "Point ajouté à '" .. param .. "'."
        end
    end
})

minetest.register_chatcommand("pathfollow", {
    params = "<nom>",
    func = function(name, param)
        if not paths[param] or #paths[param] == 0 then
            return false, "Chemin vide ou inexistant."
        end
        following_players[name] = {path = param, index = 1}
        player_yaw[name] = minetest.get_player_by_name(name):get_look_horizontal()
        create_markers(param)
        return true, "Suivi de '" .. param .. "'."
    end
})

minetest.register_chatcommand("pathclear", {
    params = "<nom>",
    func = function(name, param)
        if paths[param] then
            paths[param] = nil
            save_paths()
            clear_markers(param)
            return true, "Chemin supprimé."
        end
        return false, "Chemin inexistant."
    end
})

-- Garde en mémoire quels chemins sont visibles
local path_visible = {}

-- Correction de clear_markers pour supprimer toutes les entités
local function clear_markers(pathname)
    if markers[pathname] then
        for _, obj in ipairs(markers[pathname]) do
            if obj and obj:get_luaentity() then
                obj:remove()
            end
        end
        markers[pathname] = {}
    end

    -- Supprimer aussi toutes les entités résiduelles dans le monde
    for _, obj in ipairs(minetest.get_objects_inside_radius({x=0,y=0,z=0}, 10000)) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "pathmod:marker" then
            obj:remove()
        end
    end

    -- Marquer le chemin comme invisible
    path_visible[pathname] = false
end

-- Met à jour create_markers pour respecter path_visible
local function create_markers(pathname)
    if path_visible[pathname] == false then return end -- Ne pas recréer si caché
    clear_markers(pathname)
    markers[pathname] = {}
    markers[pathname] = {}
    local path = paths[pathname]
    if not path then return end
    for _, point in ipairs(path) do
        local obj = minetest.add_entity(point, "pathmod:marker")
        if obj then table.insert(markers[pathname], obj) end
    end
    path_visible[pathname] = true
end

-- Commande : cacher balises 3D
minetest.register_chatcommand("pathhide", {
    params = "<nom>",
    description = "Cache les balises 3D du chemin",
    func = function(name, param)
        if markers[param] and #markers[param] > 0 then
            clear_markers(param)
            return true, "Balises du chemin '" .. param .. "' cachées."
        else
            return false, "Aucune balise affichée pour ce chemin."
        end
    end
})

-- Commande : cacher toutes les balises
minetest.register_chatcommand("pathhideall", {
    description = "Cache toutes les balises 3D",
    func = function(name)
        for pathname, _ in pairs(paths) do
            clear_markers(pathname)
        end
        return true, "Toutes les balises ont été cachées."
    end
})

-- Rotation fluide + déplacement
minetest.register_globalstep(function(dtime)
    local rotation_speed = math.rad(120) -- vitesse angulaire max (120°/s)
    for name, state in pairs(following_players) do
        local player = minetest.get_player_by_name(name)
        if player then
            local path_points = paths[state.path]
            local target = path_points[state.index]
            if target then
                local pos = player:get_pos()
                local dir = vector.direction(pos, target)
                local dist = vector.distance(pos, target)

                -- Calcul Yaw cible
                local target_yaw = math.atan2(dir.z, dir.x) - math.pi / 2
                local current_yaw = player_yaw[name] or player:get_look_horizontal()
                local diff = target_yaw - current_yaw

                -- Normalisation -pi à pi
                if diff > math.pi then diff = diff - 2 * math.pi end
                if diff < -math.pi then diff = diff + 2 * math.pi end

                -- Rotation progressive
                if math.abs(diff) > rotation_speed * dtime then
                    current_yaw = current_yaw + rotation_speed * dtime * (diff > 0 and 1 or -1)
                else
                    current_yaw = target_yaw
                end
                player_yaw[name] = current_yaw
                player:set_look_horizontal(current_yaw)

                -- Vitesse
                local speed = player_speed[name] or 4

                -- Avancer
                if dist > 0.3 then
                    pos.x = pos.x + dir.x * dtime * speed
                    pos.y = pos.y + dir.y * dtime * speed
                    pos.z = pos.z + dir.z * dtime * speed
                    player:set_pos(pos)
                else
                    state.index = state.index + 1
                    if state.index > #path_points then
                        following_players[name] = nil
                        minetest.chat_send_player(name, "Chemin terminé.")
                    end
                end
            end
        end
    end
end)

