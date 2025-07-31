-- init.lua
local storage = minetest.get_mod_storage()
local paths = minetest.deserialize(storage:get_string("paths")) or {}
local markers = {} -- balises 3D visibles
local following_players = {}

-- Sauvegarde des chemins
local function save_paths()
    storage:set_string("paths", minetest.serialize(paths))
end

-- Supprimer toutes les balises
local function clear_markers(pathname)
    if markers[pathname] then
        for _, obj in ipairs(markers[pathname]) do
            if obj and obj:get_luaentity() then
                obj:remove()
            end
        end
        markers[pathname] = {}
    end
end

-- Créer les balises d’un chemin
local function create_markers(pathname)
    clear_markers(pathname)
    markers[pathname] = {}
    local path = paths[pathname]
    if not path then return end
    for _, point in ipairs(path) do
        local obj = minetest.add_entity(point, "followpath:marker")
        if obj then table.insert(markers[pathname], obj) end
    end
end

-- Définition de l’entité balise
minetest.register_entity("followpath:marker", {
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
        -- Effet de flottement léger
        local pos = self.object:get_pos()
        pos.y = pos.y + math.sin(minetest.get_gametime() * 2) * 0.005
        self.object:set_pos(pos)
    end
})

-- Commande : créer un chemin
minetest.register_chatcommand("pathnew", {
    params = "<nom>",
    description = "Crée un nouveau chemin vide",
    func = function(name, param)
        if param == "" then
            return false, "Usage: /pathnew <nom>"
        end
        paths[param] = {}
        save_paths()
        clear_markers(param)
        return true, "Chemin '" .. param .. "' créé."
    end
})

-- Commande : ajouter un point
minetest.register_chatcommand("pathadd", {
    params = "<nom>",
    description = "Ajoute la position actuelle au chemin",
    func = function(name, param)
        if not paths[param] then
            return false, "Chemin inexistant."
        end
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

-- Commande : lister chemins
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

-- Commande : afficher chemin
minetest.register_chatcommand("pathshow", {
    params = "<nom>",
    description = "Affiche les balises du chemin",
    func = function(name, param)
        if not paths[param] or #paths[param] == 0 then
            return false, "Chemin vide ou inexistant."
        end
        create_markers(param)
        return true, "Balises affichées pour '" .. param .. "'."
    end
})

-- Commande : suivre chemin
minetest.register_chatcommand("pathfollow", {
    params = "<nom>",
    description = "Suis le chemin nommé",
    func = function(name, param)
        if not paths[param] or #paths[param] == 0 then
            return false, "Chemin vide ou inexistant."
        end
        following_players[name] = {path = param, index = 1}
        create_markers(param)
        return true, "Suivi du chemin '" .. param .. "'."
    end
})

-- Commande : supprimer chemin
minetest.register_chatcommand("pathclear", {
    params = "<nom>",
    description = "Supprime un chemin",
    func = function(name, param)
        if paths[param] then
            paths[param] = nil
            save_paths()
            clear_markers(param)
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

                -- Orientation
                local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
                player:set_look_horizontal(yaw)

                -- Avancer
                local speed = 4
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

