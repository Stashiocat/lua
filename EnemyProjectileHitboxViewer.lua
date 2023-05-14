-- If lsnes complains about "module 'Super Metroid' not found", uncomment the next line and provide the path to the "Super Metroid.lua" file
-- package.path = "C:\\Games\\Lua\\Super Metroid.lua"
xemu = require("cross emu")
sm = require("Super Metroid")

if console and console.clear then
    console.clear()
elseif print then
    print("\n\n\n\n\n\n\n\n")
    print("\n\n\n\n\n\n\n\n")
end

if gui.clearGraphics then
    gui.clearGraphics()
end

-- Script options
shouldShowDisabledCollisions = false
shouldShowEmptyGridCells = false
shouldDisplayProjectileList = false
shouldDisplayProjectileHitbox = true
shouldShowEnemyHitbox = true

-- Globals
projectileList = {}
projCounts = {}
enemyProjCounts = {}

function getProjectileCellX(proj, camera)
	return math.floor((proj.x - camera.x) / 32)
end

function getProjectileCellY(proj, camera)
	return math.floor((proj.y - camera.y) / 32)
end

function getProjectileString(proj, camera)
	local cellIndexX = getProjectileCellX(proj, camera)
	local cellIndexY = getProjectileCellY(proj, camera)
	return string.format("%u: pos=(%d, %d) cell=(%d, %d)", proj.proj_idx, proj.x, proj.y, cellIndexX, cellIndexY)
end

-- Adjust drawing to account for the borders
function drawText(x, y, text, fg, bg)
    xemu.drawText(x, y, text, fg, bg or "clear")
end

function drawBox(x0, y0, x1, y1, fg, bg)
    xemu.drawBox(x0, y0, x1, y1, fg, bg or "clear")
end

function shouldDraw()
    -- The screen refresh should only be done when the game is in a valid state to draw the level data.
    -- Game state 8 is main gameplay, level data is always valid.
    -- Game states 9, Ah and Bh are the various stages of going through a door,
    -- the level data is only invalid when the door transition function is $E36E during game state Bh(?).
    -- Game states Ch..12h are the various stages of pausing and unpausing
    -- the level data is only invalid during game states Eh..10h,
    -- but Dh sets up the BG position for the map
    -- Game state 2Ah is the demo
    local gameState = sm.getGameState()
    local doorTransitionFunction = sm.getDoorTransitionFunction()

    return
           8 <= gameState and gameState < 0xB
        or 0xC <= gameState and gameState < 0xD
        or 0x11 <= gameState and gameState < 0x13
        or 0x2A == gameState
        or gameState == 0xB and doorTransitionFunction ~= 0xE36E
end

function displayEnemyHitboxes(camera)
    local y = 0
    local n_enemies = sm.getNEnemies()
    --drawText(0, 0, string.format("n_enemies: %04X", n_enemies), 0xFF00FFFF)
    if n_enemies == 0 then
        return
    end

    -- Iterate backwards, I want earlier enemies drawn on top of later ones
    for j=1,n_enemies do
        local i = n_enemies - j
        local enemyId = sm.getEnemyId(i)
        if enemyId ~= 0 then
            local enemyXPosition       = sm.getEnemyXPosition(i)
            local enemyYPosition       = sm.getEnemyYPosition(i)
            local enemyXRadius         = sm.getEnemyXRadius(i)
            local enemyYRadius         = sm.getEnemyYRadius(i)
			local enemyExtraProperties = sm.getEnemyExtraProperties(i)
			local enemyProperties      = sm.getEnemyProperties(i)
            local left   = enemyXPosition - enemyXRadius - camera.x
            local top    = enemyYPosition - enemyYRadius - camera.y
            local right  = enemyXPosition + enemyXRadius - camera.x
            local bottom = enemyYPosition + enemyYRadius - camera.y
			
			local IsCollisionEnabled = bit.band(enemyProperties, 0x400) == 0
			
			if shouldShowDisabledCollisions or IsCollisionEnabled then
				-- Draw enemy hitbox
				-- If not using extended spritemap format or frozen, draw simple hitbox
				if xemu.and_(enemyExtraProperties, 4) == 0 or sm.getEnemyAiHandler(i) == 4 then
					drawBox(left, top, right, bottom, 0xFFFFFF80, "clear")
				else
					-- Process extended spritemap format
					local p_spritemap = sm.getEnemySpritemap(i)
					if p_spritemap ~= 0 then
						local bank = xemu.lshift(sm.getEnemyBank(i), 16)
						p_spritemap = bank + p_spritemap
						local n_spritemap = xemu.read_u8(p_spritemap)
						if n_spritemap ~= 0 then
							for ii=0,n_spritemap-1 do
								local entryPointer = p_spritemap + 2 + ii*8
								local entryXOffset = xemu.read_s16_le(entryPointer)
								local entryYOffset = xemu.read_s16_le(entryPointer + 2)
								local entryHitboxPointer = xemu.read_u16_le(entryPointer + 6)
								if entryHitboxPointer ~= 0 then
									entryHitboxPointer = bank + entryHitboxPointer
									local n_hitbox = xemu.read_u16_le(entryHitboxPointer)
									if n_hitbox ~= 0 then
										for iii=0,n_hitbox-1 do
											local entryLeft   = xemu.read_s16_le(entryHitboxPointer + 2 + iii*12)
											local entryTop    = xemu.read_s16_le(entryHitboxPointer + 2 + iii*12 + 2)
											local entryRight  = xemu.read_s16_le(entryHitboxPointer + 2 + iii*12 + 4)
											local entryBottom = xemu.read_s16_le(entryHitboxPointer + 2 + iii*12 + 6)
											drawBox(
												enemyXPosition - camera.x + entryXOffset + entryLeft,
												enemyYPosition - camera.y + entryYOffset + entryTop,
												enemyXPosition - camera.x + entryXOffset + entryRight,
												enemyYPosition - camera.y + entryYOffset + entryBottom,
												0xFFFFFF80, "clear"
											)
										end
									end
								end
							end
						end
					end
				end

				-- Show enemy index and ID
				drawText(left + 16, top, string.format("%u: %04X", i, enemyId), 0xFFFFFFFF)

				-- Log enemy index and ID to list in top-right
				if logFlag ~= 0 then
					drawText(224, y, string.format("%u: %04X", i, enemyId), 0xFFFFFFFF, 0xFF)
					--drawText(192, y, string.format("%u: %04X", i, sm.getEnemyInstructionList(i)), 0xFFFFFFFF, 0xFF)
					--drawText(160, y, string.format("%u: %04X", i, sm.getEnemyAiVariable5(i)), 0xFFFFFFFF, 0xFF)
					y = y + 8
				end

				-- Show enemy health
				local enemySpawnHealth = xemu.read_u16_le(0xA00004 + enemyId)
				if enemySpawnHealth ~= 0 then
					local enemyHealth = sm.getEnemyHealth(i)
					drawText(left, top - 16, string.format("%u/%u", enemyHealth, enemySpawnHealth), 0xFFFFFF80)
					-- Draw enemy health bar
					if enemyHealth ~= 0 then
						drawBox(left, top - 8, left + enemyHealth * 32 / enemySpawnHealth, top - 5, 0xFFFFFF80, 0xFFFFFF80)
						drawBox(left, top - 8, left + 32, top - 5, 0xFFFFFF80, "clear")
					end
				end
			end
        end
    end
end

function displayEnemyProjectileHitboxes(camera)
	local y = 0
    for j=1,18 do
        -- Iterate backwards, I want earlier enemy projectiles drawn on top of later ones
        local i = 18 - j
        local enemyProjectileId = sm.getEnemyProjectileId(i)
        if enemyProjectileId ~= 0 then
            local enemyProjectileXPosition  = sm.getEnemyProjectileXPosition(i)
            local enemyProjectileYPosition  = sm.getEnemyProjectileYPosition(i)
            local enemyProjectileXRadius    = sm.getEnemyProjectileXRadius(i)
            local enemyProjectileYRadius    = sm.getEnemyProjectileYRadius(i)
			local enemyProjectileProperties = sm.getEnemyProjectileProperties(i)
			local enemyProjectilesEnabled   = sm.getEnemyProjectilesEnabled() ~= 0
            local left   = enemyProjectileXPosition - enemyProjectileXRadius - camera.x
            local top    = enemyProjectileYPosition - enemyProjectileYRadius - camera.y
            local right  = enemyProjectileXPosition + enemyProjectileXRadius - camera.x
            local bottom = enemyProjectileYPosition + enemyProjectileYRadius - camera.y

			local proj = {proj_idx=i, x = enemyProjectileXPosition, y = enemyProjectileYPosition, color = "red"}
			local cellx = getProjectileCellX(proj, camera)
			local celly = getProjectileCellY(proj, camera)
			
			local hash = cellx*10 + celly
			if enemyProjCounts[hash] ~= nil then
				local bHasCollisions = bit.band(enemyProjectileProperties, sm.enemy_projectile_detect_collisions_with_projectiles) ~= 0
				bHasCollisions = bHasCollisions and bit.band(enemyProjectileProperties, sm.enemy_projectile_disable_collisions_with_samus) == 0
				if shouldShowDisabledCollisions or bHasCollisions then
					enemyProjCounts[hash] = enemyProjCounts[hash] + 1
					
					if shouldDisplayProjectileHitbox then
						-- Draw enemy projectile hitbox
						drawBox(left, top, right, bottom, 0x00FF0080, "clear")
						--drawBox(math.min(left, right - 2), math.min(top, bottom - 2), math.max(right, left + 2), math.max(bottom, top + 2), 0x00FF0080, "clear")

						-- Show enemy projectile index and ID
						drawText(left, top, string.format("%u: %04X", i, enemyProjectileId), 0x00FF00FF)
						--drawText(left, top, string.format("%04X", xemu.read_u16_le(0x7E1B6B + i * 2)), 0x00FFFFFF, 0x000000FF)
					end
					
					table.insert(projectileList, proj)
				end
			end
		
        end
    end
end

function displayProjectileHitboxes(camera)
    for i=0,9 do
        local projectileXPosition = sm.getProjectileXPosition(i)
        local projectileYPosition = sm.getProjectileYPosition(i)
        local projectileXRadius   = sm.getProjectileXRadius(i)
        local projectileYRadius   = sm.getProjectileYRadius(i)
        local left   = projectileXPosition - projectileXRadius - camera.x
        local top    = projectileYPosition - projectileYRadius - camera.y
        local right  = projectileXPosition + projectileXRadius - camera.x
        local bottom = projectileYPosition + projectileYRadius - camera.y

		local proj = {proj_idx=i, x = projectileXPosition, y = projectileYPosition, color = "yellow"}
		local cellx = getProjectileCellX(proj, camera)
		local celly = getProjectileCellY(proj, camera)
		
		local hash = cellx*10 + celly
		if projCounts[hash] ~= nil then
			projCounts[hash] = projCounts[hash] + 1
		end
		
		if shouldDisplayProjectileHitbox then
			-- Draw projectile hitbox
			drawBox(left, top, right, bottom, 0xFFFF0080, "clear")

			-- Show projectile damage
			drawText(left, top - 8, sm.getProjectileDamage(i), 0xFFFF0080)

			-- Show bomb timer
			if i >= 5 then
				drawText(left, top - 16, sm.getBombTimer(i), 0xFFFF0080)
			end
		end
		
		table.insert(projectileList, proj)
    end
end

function displayProjectileList(camera)
	local yPos = 0
	for idx, proj in ipairs(projectileList) do
		local str = getProjectileString(proj, camera)
		drawText(0, yPos, str, proj.color)
		yPos = yPos + 8
	end
end

-- Finally, the main loop
function on_paint()
	if not shouldDraw() then
		return
	end
    
    -- Co-ordinates of the top-left of the screen
	camera = {x=sm.getLayer1XPosition(), y=sm.getLayer1YPosition()}
    
	local startX = bit.band(camera.x, 0xFFE0) - camera.x
	local startY = bit.band(camera.y, 0xFFE0) - camera.y
	
	for y_offs=0,7 do
		for x_offs=0,8 do
			projCounts[x_offs*10 + y_offs] = 0
			enemyProjCounts[x_offs*10 + y_offs] = 0
		end
	end
    
	displayProjectileHitboxes(camera)
    displayEnemyProjectileHitboxes(camera)
	
	if shouldShowEnemyHitbox then
		displayEnemyHitboxes(camera)
	end
	
	if shouldDisplayProjectileList then
		displayProjectileList(camera)
    end
	
	for y_offs=0,7 do
		for x_offs=0,8 do
			local hash = 10*x_offs + y_offs
			if enemyProjCounts[hash] > 0 or shouldShowEmptyGridCells then
				drawBox(startX + x_offs*32, startY + y_offs*32, startX + (x_offs+1)*32, startY + (y_offs+1)*32)
				drawText(startX + x_offs*32 + 1, startY + y_offs*32 + 1, string.format("%d", projCounts[hash]), "red")
				drawText(startX + x_offs*32 + 1, startY + y_offs*32 + 9, string.format("%d", enemyProjCounts[hash]), "yellow")
			end
		end
	end
end

while true do
	projectileList = {}
	projCounts = {}
	enemyProjCounts = {}
	
	on_paint()
	emu.frameadvance()
end