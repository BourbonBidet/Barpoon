local events = {}
local listeners = {}

function events.add_listener(event_name, callback)
	local callbacks = listeners[event_name]
	if not callbacks then
		callbacks = {}
	end
	for _, cb in ipairs(callbacks) do
		if cb == callback then
			return
		end
	end
	table.insert(callbacks, callback)
	listeners[event_name] = callbacks
end

function events.clear_listeners() end

function events.emit(event_name, ...)
	if not listeners then
		return
	end
	local event_callbacks = listeners[event_name]
	if event_callbacks ~= nil then
		for _, cb in ipairs(event_callbacks) do
			cb(...)
		end
	end
end

return events
