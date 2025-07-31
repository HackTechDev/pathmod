-- init.lua
local storage = minetest.get_mod_storage()
local paths = minetest.deserialize(storage:get_string("paths")) or {}
local following_players = {}

-- Sauvegarde des chemins
local function save_paths()
    storage:set_string("paths", minetest.serialize(paths))
end

-- Fonction pour afficher visuellement un chemin
local function visualize_path(pathname)
    local path = paths[pathname]
    if not path then return end

    for _, point in ipairs(path) do
        minetest.add_particle({
            pos = point,
            velocity = {x=0, y=0.2, z=0},
            acceleration = {x=0, y=0, z=0},
            expirationtime = 3,
            size = 4,
            texture = "default_mese_crystal.png",
            glow = 10,
        })
    end
end

-- Créer un nouveau chemin
minetest.register_chatcommand("pathnew", {
    params = "<nom>",
    description = "Crée un nouveau chemin vide",
    func = function(name, param)
        if param == "" then
            return false, "Usage: /pathnew <nom>"
        end
        paths[param] = {}
        save_paths()
        return true, "Chemin '" .. param .. "' créé."
    end
})

-- Ajouter un point à un chemin
minetest.register_chatcommand("pathadd", {
    params = "<nom>",
    description = "Ajoute la position actuelle au chemin nommé",
    func = function(name, param)
        if paths[param] == nil then
            return false, "Ce chemin n'existe pas."
        end
        local player = minetest.get_player_by_name(name)
        if player then
            local pos = vector.round(player:get_pos())
            table.insert(paths[param], pos)
            save_paths()
            visualize_path(param) -- Visualise à chaque ajout
            return true, "Point ajouté au chemin '" .. param .. "'."
        end
    end
})

-- Lister les chemins existants
minetest.register_chatcommand("pathlist", {
    description = "Liste tous les chemins",
    func = function(name)
        local list = {}
        for k, v in pairs(paths) do
            table.insert(list, k .. " (" .. #v .. " points)")
        end
        if #list == 0 then
            return true, "Aucun chemin défini."
        end
        return true, "Chemins : " .. table.concat(list, ", ")
    end
})

-- Visualiser un chemin
minetest.register_chatcommand("pathshow", {
    params = "<nom>",
    description = "Affiche le chemin avec des particules",
    func = function(name, param)
        if paths[param] == nil or #paths[param] == 0 then
            return false, "Ce chemin est vide ou inexistant."
        end
        visualize_path(param)
        return true, "Chemin '" .. param .. "' affiché."
    end
})

-- Suivre un chemin
minetest.register_chatcommand("pathfollow", {
    params = "<nom>",
    description = "Suis le chemin nommé",
    func = function(name, param)
        if paths[param] == nil or #paths[param] == 0 then
            return false, "Ce chemin est vide ou inexistant."
        end
        following_players[name] = {path = param, index = 1}
        visualize_path(param) -- Visualiser au démarrage
        return true, "Début du suivi du chemin '" .. param .. "'."
    end
})

-- Supprimer un chemin
minetest.register_chatcommand("pathclear", {
    params = "<nom>",
    description = "Supprime un chemin",
    func = function(name, param)
        if paths[param] then
            paths[param] = nil
            save_paths()
            return true, "Chemin '" .. param .. "' supprimé."
        end
        return false, "Ce chemin n'existe pas."
    end
})

-- Déplacement fluide du joueur
minetest.register_globalstep(function(dtime)
    for name, state in pairs(following_players) do
        local player = minetest.get_player_by_name(name)
        if player then
            local path_points = paths[state.path]
            local target = path_points[state.index]
            if target then
                local pos = player:get_pos()
                local dir = vector.direction(pos, target)
                local dist = vector.distance(pos, target)

                -- Rotation du joueur
                local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
                player:set_look_horizontal(yaw)

                -- Avancer
                local speed = 4 -- m/s
                if dist > 0.3 then
                    pos.x = pos.x + dir.x * dtime * speed
                    pos.y = pos.y + dir.y * dtime * speed
                    pos.z = pos.z + dir.z * dtime * speed
                    player:set_pos(pos)
                else
                    -- Prochain point
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

-- Mise à jour régulière de la visualisation (toutes les 3 secondes)
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= 3 then
        for pathname, _ in pairs(paths) do
            visualize_path(pathname)
        end
        timer = 0
    end
end)

