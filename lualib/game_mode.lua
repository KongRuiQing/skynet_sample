local skynet = require "skynet"
local log = require "log"
local PlayerClass = require "player"
local game_table = require "game_table"
local log = require "log"
local CardHelp = require "CardHelp"
local queue = require "skynet.queue"

local K = {}
local MatchState = {
	EnteringMap = 1,
	WaitingToStart = 2,
	InProgress = 3,
	WaitingPostMatch = 4,
	LeavingMap = 5,
	Aborted = 6,
}

local TableState = {
	Init = 1,
	Waiting = 2,
	GameResult = 3,
}

local CMDType = {
	CHU_PAI = 1
}

function K:newTimer(loop)
	local o = {}
	local obj = self

	local timer_func = function()
		log("Tick one second")
		obj:gameTimer(1)
		if loop then
			skynet.timeout(1*100,o)
		end
	end
	setmetatable(o,{__call = timer_func})
	return o
end


function K.new()
	local o = {}
	setmetatable(o,{__index = K })
	--K.init(o)
	return o
end

function K:init()
	self._matchState = 0
	self._needPlayerNum = 4
	self.lock = queue()
	self._tableState = TableState.Init
	self._table = game_table.new()
	self._player = {}
	self._currentIndex = 0
	self._step = 0
end

function K:addMaster(agent)
	local n = math.random(self._needPlayerNum)
	self._player[n] = PlayerClass.new(agent,n)
	self._player[n]:setMaster()
	self._masterIndex = n
	return n
end

function K:create(data)
	self:init()
	self._agent = data._agent
end

function K:addPlayer(agent)
	local n = math.random(self._needPlayerNum)
	while self._player[n] do
		n = (n) % self._needPlayerNum + 1
	end
	self._player[n] = PlayerClass.new(agent,n)
	return n
end

function K:addRobot()
	local num = self:getPlayerNum()
	if num >= self._needPlayerNum then
		return nil
	end
	local robot_id = self._masterIndex % self._needPlayerNum + 1
	while self._player[robot_id] do
		robot_id = ((robot_id) % self._needPlayerNum) + 1
	end
	log("%d addRobot robot_id %d",skynet.self(),robot_id)

	self._player[robot_id] = PlayerClass.robot(robot_id)
	self.lock(self.BroadcastPlayerJoin,self,robot_id)
	return self._player[robot_id]
end

function K:BroadcastPlayerJoin(player_id)
	local player = self._player[player_id]
	for agent_id,player_index in pairs(self._agent) do
		--log("send proto(onPlayerJoin) agent_id %d player_index %d",agent_id,player_index)
		skynet.send(agent_id,"lua","onPlayerJoin",{
			name = player:getName(),
			is_ready = player:isReady(),
			player_index = player:getIndex()
		})
	end
end


function K:HandleMatchIsWaitingToStart()
	self._table:init()
end

function K:HandleMatchHasStarted()
	self._table:create()
	self._table:shuffle()
	self._currentIndex = 1
	self._step = 1
	for i=1,3 do
		for j = 1,4 do
			local card_list = self._table:getCards(4)
			self._player[j]:giveCards(card_list)
		end
	end
	local card_list = self._table:getCards(2)
	self._player[1]:giveCards(card_list)
	for i = 2,4 do
		local card_list = self._table:getCards(1)
		self._player[i]:giveCards(card_list)
	end
	self.lock(self.broadcastGamePlayCard,self)
end


function K:gameTimer()
	if self._matchState == MatchState.InProgress then
		self._tickTime = self._tickTime + 1
		if self._tableState == TableState.Wait then
			if self._tickTime >= 20 then
				-- 当前玩家扔一张,进行下一个
			end
		end
	end
end

function K:broadcastGamePlayCard()
	for agent_id,player_index in pairs(self._agent) do
		local card_in_hand = self._player[player_index]:getCards()
		local other = {}
		for player_index,player in pairs(self._player) do
			other[player_index] = player:getCardsNumInHand()
			log("player %d card num in hand %d", player_index,player:getCardsNumInHand())
		end

		--log("player %d card_in hand %s",player_index,table.concat(card_in_hand,","))
		skynet.send(agent_id,"lua","onStartGame",{
			hand_card = card_in_hand,
			other = other,
		})
	end

	self._tableState = TableState.Wait
	self._currentIndex = 1
	self._step = 1
end

function K:onMatchStateSet()
	if self._matchState == MatchState.WaitingToStart then
		self:HandleMatchIsWaitingToStart()
	elseif self._matchState == MatchState.InProgress then
		self:HandleMatchHasStarted()
	end
end

function K:setMatchState(matchState)
	if matchState == self._matchState then
		return
	end
	self._matchState = matchState
	self:onMatchStateSet()
end

function K:getPlayerNum()
	local n = 0
	for _,_ in pairs(self._player) do
		n = n + 1
	end
	return n
end

function K:startGame()
	self:setMatchState(MatchState.InProgress)
end

function K:useCard(player_index,cmd,card)
	if cmd == CMDType.CHU_PAI then
		if self._currentIndex ~= player_index then
			return false
		end

		local player = self._player[player_index]
		local success = player.useCard(card)
		if not success then
			return false
		end

		local next = true
		for i,p in pairs(self._player) do
			if i ~= player_index then
				local notify_card_state = p:testCard(card)
				if notify_card_state ~= nil then
					next = false
					if player:getAgent() then
						self.lock()
					end
				end
			end
		end
		self._currentIndex = self._currentIndex % self._needPlayerNum + 1
		if next then
			local give_card = self._table:getCards(1)
			local nextPlayer = self._player[self._currentIndex]
			nextPlayer:giveCards(give_card)
			if nextPlayer:getAgent() then

			end
		end
	end
end

function K:use_CHU_card()

end

function K:use_CHI_card()

end

function K:use_PENG_card()
end
function K:use_GANG_card()
end
function K:use_HU_card()

end

return K
