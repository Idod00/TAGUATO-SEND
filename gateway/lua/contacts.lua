-- CRUD endpoints for contact lists and items
-- Requires auth.lua (ngx.ctx.user set)

local db = require "init"
local json = require "json"
local cjson = require "cjson"
local validate = require "validate"

local empty_array_mt = cjson.empty_array_mt
local function as_array(t)
    if t == nil or (type(t) == "table" and #t == 0) then
        return setmetatable({}, empty_array_mt)
    end
    return t
end

local user = ngx.ctx.user
if not user then
    json.respond(401, { error = "Unauthorized" })
    return
end

local method = ngx.req.get_method()
local uri = ngx.var.uri

-- Parse URI patterns
local list_id = uri:match("^/api/contacts/(%d+)$")
local items_list_id = uri:match("^/api/contacts/(%d+)/items$")
local item_parts = uri:match("^/api/contacts/%d+/items/(%d+)$")
local item_list_id, item_id
if item_parts then
    item_list_id = uri:match("^/api/contacts/(%d+)/items/%d+$")
    item_id = uri:match("^/api/contacts/%d+/items/(%d+)$")
end

-- Helper: verify list ownership
local function owns_list(lid)
    local res = db.query(
        "SELECT id FROM taguato.contact_lists WHERE id = $1 AND user_id = $2",
        lid, user.id
    )
    return res and #res > 0
end

-- GET /api/contacts - List all contact lists
if method == "GET" and uri == "/api/contacts" then
    local res, err = db.query(
        [[SELECT cl.id, cl.name, cl.created_at, cl.updated_at,
                 (SELECT COUNT(*) FROM taguato.contact_list_items WHERE list_id = cl.id) as item_count
          FROM taguato.contact_lists cl
          WHERE cl.user_id = $1
          ORDER BY cl.updated_at DESC]],
        user.id
    )
    if not res then
        json.respond(500, { error = "Failed to list contacts" })
        return
    end
    json.respond(200, { lists = as_array(res) })
    return
end

-- POST /api/contacts - Create contact list
if method == "POST" and uri == "/api/contacts" then
    local body, err = json.read_body()
    if not body or not body.name then
        json.respond(400, { error = "name is required" })
        return
    end
    local res, err = db.query(
        [[INSERT INTO taguato.contact_lists (user_id, name)
          VALUES ($1, $2)
          RETURNING id, name, created_at, updated_at]],
        user.id, body.name
    )
    if not res or #res == 0 then
        json.respond(500, { error = "Failed to create list" })
        return
    end
    json.respond(201, { list = res[1] })
    return
end

-- GET /api/contacts/{id} - Get list with items
if method == "GET" and list_id and not items_list_id then
    if not owns_list(list_id) then
        json.respond(404, { error = "List not found" })
        return
    end
    local list_res = db.query(
        "SELECT id, name, created_at, updated_at FROM taguato.contact_lists WHERE id = $1 AND user_id = $2",
        list_id, user.id
    )
    if not list_res or #list_res == 0 then
        json.respond(404, { error = "List not found" })
        return
    end
    local items = db.query(
        "SELECT id, phone_number, label, created_at FROM taguato.contact_list_items WHERE list_id = $1 ORDER BY id",
        list_id
    )
    local result = list_res[1]
    result.items = as_array(items)
    json.respond(200, { list = result })
    return
end

-- PUT /api/contacts/{id} - Rename list
if method == "PUT" and list_id and not items_list_id then
    local body, err = json.read_body()
    if not body or not body.name then
        json.respond(400, { error = "name is required" })
        return
    end
    local res, err = db.query(
        "UPDATE taguato.contact_lists SET name = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3 RETURNING id, name, updated_at",
        body.name, list_id, user.id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "List not found" })
        return
    end
    json.respond(200, { list = res[1] })
    return
end

-- DELETE /api/contacts/{id} - Delete list (cascades items)
if method == "DELETE" and list_id and not item_id then
    local res, err = db.query(
        "DELETE FROM taguato.contact_lists WHERE id = $1 AND user_id = $2 RETURNING id, name",
        list_id, user.id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "List not found" })
        return
    end
    json.respond(200, { deleted = res[1] })
    return
end

-- POST /api/contacts/{id}/items - Add item(s) to list
if method == "POST" and items_list_id then
    if not owns_list(items_list_id) then
        json.respond(404, { error = "List not found" })
        return
    end
    local body, err = json.read_body()
    if not body then
        json.respond(400, { error = "Invalid JSON body" })
        return
    end
    -- Support single item or array of items
    local items = body.items or {{ phone_number = body.phone_number, label = body.label or "" }}
    local added = {}
    for _, item in ipairs(items) do
        if item.phone_number and item.phone_number ~= "" then
            local phone_ok, phone_err = validate.validate_phone(item.phone_number)
            if not phone_ok then
                json.respond(400, { error = phone_err .. " (" .. tostring(item.phone_number) .. ")" })
                return
            end
            local res = db.query(
                "INSERT INTO taguato.contact_list_items (list_id, phone_number, label) VALUES ($1, $2, $3) RETURNING id, phone_number, label, created_at",
                items_list_id, item.phone_number, item.label or ""
            )
            if res and #res > 0 then
                added[#added + 1] = res[1]
            end
        end
    end
    db.query("UPDATE taguato.contact_lists SET updated_at = NOW() WHERE id = $1", items_list_id)
    json.respond(201, { items = as_array(added) })
    return
end

-- DELETE /api/contacts/{list_id}/items/{item_id} - Remove item
if method == "DELETE" and item_list_id and item_id then
    if not owns_list(item_list_id) then
        json.respond(404, { error = "List not found" })
        return
    end
    local res, err = db.query(
        "DELETE FROM taguato.contact_list_items WHERE id = $1 AND list_id = $2 RETURNING id",
        item_id, item_list_id
    )
    if not res or #res == 0 then
        json.respond(404, { error = "Item not found" })
        return
    end
    db.query("UPDATE taguato.contact_lists SET updated_at = NOW() WHERE id = $1", item_list_id)
    json.respond(200, { deleted = { id = tonumber(item_id) } })
    return
end

json.respond(404, { error = "Not found" })
