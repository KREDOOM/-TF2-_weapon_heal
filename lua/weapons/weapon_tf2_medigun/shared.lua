AddCSLuaFile()

-- Загружаем частицы из TF2 Classified (для лучей) и оригинального TF2 (для искр 100% заряда)
game.AddParticles("particles/weapon_medic_medigun.pcf")
game.AddParticles("particles/entity_player_uber.pcf")

-- PrecacheParticleSystem работает и на клиенте, и на сервере; серверный вызов
-- сам прекешит частицу всем клиентам (вызывается в общем (shared) файле).
for _, particleName in ipairs({
	"SYS_medigun_red",
	"SYS_medigun_uber_red",
	"SYS_uber_muzzle_red"
}) do
	PrecacheParticleSystem(particleName)
end

if CLIENT then
	SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/weapon_tf2_medigun")
	SWEP.DrawWeaponInfoBox = true
	SWEP.BounceWeaponIcon = false

	-- Ручная отрисовка квадратной иконки 512x512 без сплющивания
	function SWEP:DrawWeaponSelection(x, y, wide, tall, alpha)
		surface.SetDrawColor(255, 255, 255, alpha)
		surface.SetTexture(self.WepSelectIcon)

		-- Вычисляем квадратный размер по высоте слота, чтобы сохранить пропорции 1:1
		local iconSize = tall * 0.9
		local iconX = x + (wide - iconSize) * 0.5
		local iconY = y + (tall - iconSize) * 0.5

		surface.DrawTexturedRect(iconX, iconY, iconSize, iconSize)

		-- Отрисовка стандартного окна с подсказкой SWEP.Instructions при выборе оружия
		self:PrintWeaponInfo(x + wide + 20, y + tall * 0.95, alpha)
	end

	-- Кешируем текстуру прицела: GetTextureID каждый кадр — лишняя работа
	MG_CrosshairTexture = surface.GetTextureID("sprites/crosshair_4")

	-- Прекеш моделей оружия (раньше они не прекешились и на первом
	-- спавне мигали «шашечками»)
	util.PrecacheModel(SWEP.ViewModel)
	util.PrecacheModel(SWEP.WorldModel)

	surface.CreateFont("MedigunHUDSmall", {
		font = "Trebuchet MS",
		size = 16,
		weight = 500,
		antialias = true
	})

	surface.CreateFont("MedigunHUDMedium", {
		font = "Trebuchet MS",
		size = 20,
		weight = 600,
		antialias = true
	})

	surface.CreateFont("MedigunHUDLarge", {
		font = "Trebuchet MS",
		size = 24,
		weight = 800,
		antialias = true
	})
end

SWEP.PrintName = "Лечебная пушка (Medi Gun)"
SWEP.Category = "Team Fortress 2"
SWEP.Author = "TF2 Medic"
SWEP.Instructions = "ЛКМ (зажать): Лечение цели и накопление заряда | ПКМ: Активировать Убер-заряд (при 100%)"
SWEP.Spawnable = true
SWEP.AdminSpawnable = true
SWEP.AdminOnly = false

SWEP.ViewModelFOV = 65
SWEP.ViewModel = "models/weapons/v_models/v_medigun_medic.mdl"
SWEP.WorldModel = "models/weapons/w_models/w_medigun.mdl"
SWEP.ViewModelFlip = false
SWEP.BobScale = 1
SWEP.SwayScale = 0

SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Weight = 3
SWEP.Slot = 1
SWEP.SlotPos = 0

SWEP.UseHands = false
SWEP.HoldType = "physgun"
SWEP.FiresUnderwater = true
SWEP.DrawCrosshair = false
SWEP.DrawAmmo = false
SWEP.CSMuzzleFlashes = 1
SWEP.Base = "weapon_base"

SWEP.WalkSpeed = 214
SWEP.RunSpeed = 428

SWEP.HealRange = 350
SWEP.UberMax = 100
SWEP.UberDuration = 8
-- Не лечить сквозь стены: пересчёт видимости цели не чаще раза в 0.1 с
SWEP.LOSCheckInterval = 0.1

SWEP.HealSoundPath = "weapons/medigun_heal.wav"
SWEP.DetachSoundPath = "weapons/medigun_heal_detach.wav"
SWEP.NoTargetSoundPath = "weapons/medigun_no_target.wav"
SWEP.ChargedSoundPath = "weapons/medigun_charged.wav"

-- Пути нужны для CreateSound (циклы), короткие алиасы — для EmitSound.
SWEP.Primary.Sound = SWEP.HealSoundPath
SWEP.DetachSound = SWEP.DetachSoundPath
SWEP.NoTargetSound = SWEP.NoTargetSoundPath
SWEP.UberSound = SWEP.ChargedSoundPath

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 0.2

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	self.Idle = 0
	self.IdleTimer = CurTime() + 1
	self.NextHealTick = 0
	self.NextUberTick = 0
	self.NextLOSCheck = 0
	self.NextRetargetCheck = 0
	self.HealSoundPlaying = false

	self:SetNWBool("MG_Healing", false)
	self:SetNWBool("MG_UberActive", false)
	self:SetNWFloat("MG_UberCharge", 0)
	self:SetNWFloat("MG_UberEndTime", 0)
	self:SetNWEntity("MG_HealTarget", NULL)
end

-- Скорость: запоминаем исходные значения игрока и возвращаем именно их,
-- а не жёсткие 200/400 (иначе ломаются другие аддоны и после смерти
-- игрок остаётся с ускорением медика).
function SWEP:ApplyOwnerSpeed()
	local owner = self:GetOwner()
	if not IsValid(owner) or not owner.SetWalkSpeed then return end

	if self.SavedWalkSpeed == nil then
		self.SavedWalkSpeed = owner:GetWalkSpeed()
		self.SavedRunSpeed = owner:GetRunSpeed()
	end

	owner:SetWalkSpeed(self.WalkSpeed)
	owner:SetRunSpeed(self.RunSpeed)
end

function SWEP:RestoreOwnerSpeed()
	local owner = self:GetOwner()
	if IsValid(owner) and owner.SetWalkSpeed then
		owner:SetWalkSpeed(self.SavedWalkSpeed or 200)
		owner:SetRunSpeed(self.SavedRunSpeed or 400)
	end

	self.SavedWalkSpeed = nil
	self.SavedRunSpeed = nil
end

-- Цель под прицелом: игрок / NPC / NextBot с положительным здоровьем
function SWEP:FindHealTarget()
	local owner = self:GetOwner()
	if not IsValid(owner) then return NULL end

	local tr = util.TraceHull({
		start = owner:EyePos(),
		endpos = owner:EyePos() + owner:EyeAngles():Forward() * self.HealRange,
		filter = owner,
		mins = Vector(-16, -16, -16),
		maxs = Vector(16, 16, 16),
		mask = MASK_SHOT_HULL
	})

	local target = tr.Entity
	if IsValid(target)
		and (target:IsPlayer() or target:IsNPC() or target:IsNextBot())
		and target:Health() > 0 then
		return target
	end

	return NULL
end

-- Есть ли прямая видимость до цели (лечение сквозь стены запрещено)
function SWEP:HasLineOfSight(target)
	local owner = self:GetOwner()
	if not IsValid(owner) or not IsValid(target) then return false end

	local tr = util.TraceLine({
		start = owner:EyePos(),
		endpos = target:WorldSpaceCenter(),
		filter = { owner, target },
		mask = MASK_VISIBLE
	})

	return not tr.Hit
end

if CLIENT then
	function SWEP:StopClientBeam()
		if self.ClientBeam and self.ClientBeam:IsValid() then
			self.ClientBeam:StopEmissionAndDestroyImmediately()
		end
		self.ClientBeam = nil
		self.LastBeamTarget = nil
		self.LastBeamUber = nil
		self.LastBeamFirstPerson = nil
	end

	function SWEP:StopChargeEffect()
		if self.ChargeEffect and self.ChargeEffect:IsValid() then
			self.ChargeEffect:StopEmissionAndDestroyImmediately()
		end
		self.ChargeEffect = nil
		self.LastChargeFirstPerson = nil
	end

		function SWEP:UpdateClientEffects(muzzlePos, muzzleAng, isFirstPerson)
		local owner = self:GetOwner()
		if not IsValid(owner) or owner:GetActiveWeapon() ~= self then
			self:StopClientBeam()
			self:StopChargeEffect()
			return
		end

		local isHealing = self:GetNWBool("MG_Healing", false)
		local target = self:GetNWEntity("MG_HealTarget", NULL)
		local isUber = self:GetNWBool("MG_UberActive", false)
		local isFullCharge = (self:GetNWFloat("MG_UberCharge", 0) >= self.UberMax)

		-- Разделяем привязку: для 1-го лица вешаем на игрока (owner), для 3-го — строго на пушку (self)
		local parentEnt = isFirstPerson and owner or self
		local attId = self:LookupAttachment("muzzle")
		local useAttachment = (not isFirstPerson and attId and attId > 0)
		local attachMode = useAttachment and PATTACH_POINT_FOLLOW or PATTACH_CUSTOMORIGIN
		local attachPoint = useAttachment and attId or 0

		-- 1. Искры на дуле при 100% заряде
		if isFullCharge and not isUber then
			if not self.ChargeEffect or not self.ChargeEffect:IsValid() or self.LastChargeFirstPerson ~= isFirstPerson then
				self:StopChargeEffect()
				self.ChargeEffect = CreateParticleSystem(parentEnt, "SYS_uber_muzzle_red", attachMode, attachPoint)
				self.LastChargeFirstPerson = isFirstPerson
			end

			if not useAttachment and self.ChargeEffect and self.ChargeEffect:IsValid() then
				self.ChargeEffect:SetControlPoint(0, muzzlePos)
				self.ChargeEffect:SetControlPointForwardVector(0, muzzleAng:Forward())
			end
		else
			self:StopChargeEffect()
		end

		-- 2. Луч лечения
		if not isHealing or not IsValid(target) then
			self:StopClientBeam()
			return
		end

		if not self.ClientBeam or not self.ClientBeam:IsValid()
			or self.LastBeamTarget ~= target
			or self.LastBeamUber ~= isUber
			or self.LastBeamFirstPerson ~= isFirstPerson then

			self:StopClientBeam()

			local effectName = isUber and "SYS_medigun_uber_red" or "SYS_medigun_red"
			self.ClientBeam = CreateParticleSystem(parentEnt, effectName, attachMode, attachPoint)

			self.LastBeamTarget = target
			self.LastBeamUber = isUber
			self.LastBeamFirstPerson = isFirstPerson
		end

		if self.ClientBeam and self.ClientBeam:IsValid() then
			if not useAttachment then
				self.ClientBeam:SetControlPoint(0, muzzlePos)
				self.ClientBeam:SetControlPointForwardVector(0, muzzleAng:Forward())
			end

			local targetPos = target:WorldSpaceCenter()
			local spineBone = target:LookupBone("ValveBiped.Bip01_Spine2")
			if not spineBone or spineBone < 0 then
				spineBone = target:LookupBone("spine 2")
			end

			if spineBone and spineBone >= 0 then
				local bPos = target:GetBonePosition(spineBone)
				if bPos and bPos ~= target:GetPos() then
					targetPos = bPos
				end
			end

			self.ClientBeam:SetControlPoint(1, targetPos)
		end
	end

-- Рендер эффектов от 1-го лица ДО отрисовки кадра (убирает отставание при повороте камеры)
hook.Add("PreDrawTranslucentRenderables", "TF2_Medigun_FirstPersonBeam", function(bDepth, bSkybox)
	if bSkybox or bDepth then return end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or ply:ShouldDrawLocalPlayer() then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or not wep.UpdateClientEffects then return end

	-- Используем глобальные EyePos и EyeAngles рендера вместо сетевых данных игрока
	local camPos = EyePos()
	local camAng = EyeAngles()
	local muzzlePos = camPos + camAng:Forward() * 32 + camAng:Right() * 9 - camAng:Up() * 7

	wep:UpdateClientEffects(muzzlePos, camAng, true)
end)

	-- Рендер мировой модели (от 3-го лица) без шланга
	local WorldModelScale = 0.75
	local WorldModelOffsetPos = Vector(-3, -2, -6)
	local WorldModelOffsetAng = Angle(0, 0, 180)
	local ZeroBoneScale = Vector(0, 0, 0)

	-- Скрытие костей шланга и масштаб модели — один раз, а не каждый кадр
	-- (SetModelScale к тому же портит физику брошенного оружия).
	function SWEP:SetupWorldModelOnce()
		if self.WorldModelPrepared then return end
		self.WorldModelPrepared = true

		local boneCount = self:GetBoneCount() or 0
		for i = 0, boneCount - 1 do
			local bName = self:GetBoneName(i)
			if bName and string.find(string.lower(bName), "hose") then
				self:ManipulateBoneScale(i, ZeroBoneScale)
			end
		end

		self:SetModelScale(WorldModelScale, 0)
	end

	function SWEP:DrawWorldModel()
		self:SetupWorldModelOnce()

		local owner = self:GetOwner()
		if IsValid(owner) then
			local boneId = owner:LookupBone("ValveBiped.Bip01_R_Hand")
			if boneId then
				local matrix = owner:GetBoneMatrix(boneId)
				if matrix then
					local pos, ang = LocalToWorld(WorldModelOffsetPos, WorldModelOffsetAng, matrix:GetTranslation(), matrix:GetAngles())
					self:SetRenderOrigin(pos)
					self:SetRenderAngles(ang)
				end
			end
		end

		self:SetupBones()
		self:DrawModel()

		self:UpdateClientEffects(self:GetPos(), self:GetAngles(), false)
	end
end

function SWEP:StopChargedSound()
	if self.ChargedSoundPatch then
		self.ChargedSoundPatch:Stop()
		self.ChargedSoundPatch = nil
	end
end

-- Непрерывный звук лечения. Файл medigun_heal.wav не содержит loop-точек,
-- поэтому обычный EmitSound обрывался через 4 секунды — держим CSoundPatch
-- и перезапускаем его, пока лечение активно.
function SWEP:StartHealSound()
	if not SERVER then return end
	if self.HealSoundPlaying then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	self.HealSoundPlaying = true
	self:PlayHealSoundLoop()

	-- medigun_heal.wav ≈ 4.0 c и без loop-точек: перезапускаем чуть раньше,
	-- чтобы звук не прерывался, пока игрок держит ЛКМ.
	local timerName = "TF2_MedigunHealLoop" .. self:EntIndex()
	timer.Create(timerName, 3.9, 0, function()
		if not IsValid(self) then
			timer.Remove(timerName)
			return
		end
		if self.HealSoundPlaying and self:GetNWBool("MG_Healing", false) then
			self:PlayHealSoundLoop()
		else
			timer.Remove(timerName)
		end
	end)
end

function SWEP:PlayHealSoundLoop()
	if not SERVER or not self.HealSoundPlaying then return end
	if not self:GetNWBool("MG_Healing", false) then
		self:StopHealing()
		return
	end

	local owner = self:GetOwner()
	if not IsValid(owner) then
		self.HealSoundPlaying = false
		return
	end

	if self.HealSoundPatch then
		self.HealSoundPatch:Stop()
	end

	self.HealSoundPatch = CreateSound(owner, self.HealSoundPath)
	if self.HealSoundPatch then
		self.HealSoundPatch:Play()
		self.HealSoundPatch:ChangeVolume(self:GetNWBool("MG_UberActive", false) and 0.5 or 0.8, 0)
	end
end

function SWEP:Deploy()
	self:SetHoldType(self.HoldType)
	self:SendWeaponAnim(ACT_VM_DRAW)
	self:SetNextPrimaryFire(CurTime() + 0.5)
	self:SetNextSecondaryFire(CurTime() + 0.5)

	local owner = self:GetOwner()
	if IsValid(owner) then
		local vm = owner:GetViewModel()
		self.IdleTimer = CurTime() + (IsValid(vm) and vm:SequenceDuration() or 1)
		self:ApplyOwnerSpeed()
	end

	self.Idle = 0
	self:StopHealing()
	return true
end

function SWEP:Holster()
	self:StopHealing()
	self:StopChargedSound()

	if self:GetNWBool("MG_UberActive", false) then
		self:EndUberCharge()
	end

	if CLIENT then
		self:StopClientBeam()
		self:StopChargeEffect()
	end

	self:RestoreOwnerSpeed()

	return true
end

function SWEP:StopHealing()
	if self.HealSoundPatch then
		self.HealSoundPatch:Stop()
		self.HealSoundPatch = nil
	end
	self.HealSoundPlaying = false

	if CLIENT then
		self:StopClientBeam()
	end

	if self:GetNWBool("MG_Healing", false) then
		-- Звук отрыва — только на сервере: он сам рассылается всем клиентам,
		-- иначе предсказанный клиентский EmitSound играет его вторым слоем.
		if SERVER then
			self:EmitSound(self.DetachSound)
		end

		self:SetNWBool("MG_Healing", false)
		self:SetNWEntity("MG_HealTarget", NULL)
		self.Idle = 0
		self.IdleTimer = CurTime()
	end
end

-- Убер-защита должна всегда висеть на текущем пациенте, а не на первом,
-- кого лечили: если старый умер/убежал, защита переносится на нового.
function SWEP:UpdateUberTarget(target)
	if not SERVER then return end
	if not self:GetNWBool("MG_UberActive", false) then return end

	local oldTarget = self.UberTarget
	if oldTarget == target then return end

	if IsValid(oldTarget) then
		oldTarget.MG_UberProtected = nil
		if oldTarget:IsPlayer() then
			oldTarget:GodDisable()
			oldTarget:ChatPrint("МЕДИК: Ты больше не под убер-зарядом.")
		end
	end

	if IsValid(target) then
		target.MG_UberProtected = true
		if target:IsPlayer() then
			target:GodEnable()
			target:ChatPrint("МЕДИК: Ты неуязвим! В атаку!")
		end
		self.UberTarget = target
	else
		self.UberTarget = nil
	end
end

function SWEP:PrimaryAttack()
	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	-- Функция предсказывается на клиенте и сервере: сетевые
	-- NW-переменные меняет только сервер.
	if not SERVER then
		-- держим предсказанный таймер, чтобы движок не звал нас каждый тик
		self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
		return
	end

	-- Уже лечим — не блокируем атаку, а просто обновляем звук и таймер,
	-- смена цели идёт в Think. Иначе цель нельзя было переключить.
	if self:GetNWBool("MG_Healing", false) then
		self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
		return
	end

	local target = self:FindHealTarget()
	if not IsValid(target) then
		self:EmitSound(self.NoTargetSound)
		self:SetNextPrimaryFire(CurTime() + 0.25)
		return
	end

	self:SetNWBool("MG_Healing", true)
	self:SetNWEntity("MG_HealTarget", target)
	self:StartHealSound()
	self:UpdateUberTarget(target)

	owner:SetAnimation(PLAYER_ATTACK1)
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	self.Idle = 1
end

function SWEP:SecondaryAttack()
	-- Убер — полностью серверное состояние; клиенту остаётся только подсказка.
	if not SERVER then
		if IsFirstTimePredicted() and self:GetNWFloat("MG_UberCharge", 0) < self.UberMax then
			LocalPlayer():ChatPrint("Убер-заряд не готов! (" .. math.Round(self:GetNWFloat("MG_UberCharge", 0)) .. "%)")
		end
		self:SetNextSecondaryFire(CurTime() + 0.5)
		return
	end

	local charge = self:GetNWFloat("MG_UberCharge", 0)
	local isUber = self:GetNWBool("MG_UberActive", false)

	if charge >= self.UberMax and not isUber then
		self:ActivateUberCharge()
		self:SetNextSecondaryFire(CurTime() + 1.0)
	else
		self:SetNextSecondaryFire(CurTime() + 0.5)
	end
end

function SWEP:ActivateUberCharge()
	if not SERVER then return end
	if self:GetNWBool("MG_UberActive", false) then return end
	if self:GetNWFloat("MG_UberCharge", 0) < self.UberMax then return end

	-- Запоминаем, лечим ли кого-то: убер не должен прерывать лечение
	local target = self:GetNWEntity("MG_HealTarget", NULL)
	local wasHealing = self:GetNWBool("MG_Healing", false)

	self:SetNWBool("MG_UberActive", true)
	self:SetNWFloat("MG_UberEndTime", CurTime() + self.UberDuration)
	self:SetNWFloat("MG_UberCharge", 0)
	self:StopChargedSound()

	local owner = self:GetOwner()
	if IsValid(owner) then
		owner:GodEnable()
		owner.MG_UberProtected = true
		owner:ChatPrint("МЕДИК: Убер-заряд активирован на " .. self.UberDuration .. " секунд!")
	end

	self.UberTarget = nil
	if wasHealing and IsValid(target) then
		self:UpdateUberTarget(target)
	end

	-- Под убером звук лечения тише (главный звук — убер)
	if wasHealing then
		if not self.HealSoundPlaying then
			self:StartHealSound()
		elseif self.HealSoundPatch then
			self.HealSoundPatch:ChangeVolume(0.5, 0.2)
		end
	end

	self:EmitSound(self.UberSound)
end

function SWEP:EndUberCharge()
	if not SERVER then return end
	if not self:GetNWBool("MG_UberActive", false) then return end

	self:SetNWBool("MG_UberActive", false)

	local owner = self:GetOwner()
	if IsValid(owner) then
		owner:GodDisable()
		owner.MG_UberProtected = nil
		owner:ChatPrint("МЕДИК: Убер-заряд закончился!")
	end

	if IsValid(self.UberTarget) then
		if self.UberTarget:IsPlayer() then
			self.UberTarget:GodDisable()
			self.UberTarget:ChatPrint("МЕДИК: Неуязвимость закончилась!")
		end
		self.UberTarget.MG_UberProtected = nil
		self.UberTarget = nil
	end
end

function SWEP:Think()
	if CLIENT then
		if not self:GetNWBool("MG_Healing", false) then
			self:StopClientBeam()
		end
		if self:GetNWFloat("MG_UberCharge", 0) < self.UberMax or self:GetNWBool("MG_UberActive", false) then
			self:StopChargeEffect()
		end
		return
	end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	local curTime = CurTime()
	local isUber = self:GetNWBool("MG_UberActive", false)
	local isHealing = self:GetNWBool("MG_Healing", false)

	-- Если оружие убрали/сменили — снимаем баффы скорости и лечение,
	-- иначе состояние остаётся висеть на игроке.
	if owner:GetActiveWeapon() ~= self then
		self:StopHealing()
		self:StopChargedSound()
		self:RestoreOwnerSpeed()
		if isUber then
			self:EndUberCharge()
		end
		return
	end

	-- Фоновый звук 100% Убер-заряда со встроенным циклом движка Source
	local isFullCharge = (self:GetNWFloat("MG_UberCharge", 0) >= self.UberMax)

	if isFullCharge and not isUber then
		if not self.ChargedSoundPatch then
			self.ChargedSoundPatch = CreateSound(owner, self.ChargedSoundPath)
			if self.ChargedSoundPatch then
				self.ChargedSoundPatch:Play()
				self.ChargedSoundPatch:ChangeVolume(0.75, 0)
			end
		end
	else
		self:StopChargedSound()
	end

	if isUber and curTime >= self:GetNWFloat("MG_UberEndTime", 0) then
		self:EndUberCharge()
	end

	if isHealing then
		local target = self:GetNWEntity("MG_HealTarget", NULL)
		local targetValid = IsValid(target) and target:Health() > 0
		local tooFar = targetValid and owner:EyePos():Distance(target:GetPos()) > (self.HealRange * 1.15)

		if not targetValid or not owner:KeyDown(IN_ATTACK) or tooFar then
			if tooFar then
				owner:ChatPrint("Цель слишком далеко! Лечение прервано.")
			end
			self:StopHealing()
			return
		end

		-- Лечение сквозь стены запрещено: без линии видимости луч рвётся
		if curTime >= (self.NextLOSCheck or 0) then
			self.NextLOSCheck = curTime + self.LOSCheckInterval
			if not self:HasLineOfSight(target) then
				self:StopHealing()
				return
			end
		end

		-- Мягкое перенацеливание: смотрим на другого пациента — переключаемся
		if curTime >= (self.NextRetargetCheck or 0) then
			self.NextRetargetCheck = curTime + 0.2
			local newTarget = self:FindHealTarget()
			if IsValid(newTarget) and newTarget ~= target then
				self:SetNWEntity("MG_HealTarget", newTarget)
				self:UpdateUberTarget(newTarget)
				target = newTarget
			end
		end

		if curTime >= (self.NextHealTick or 0) then
			local maxHp = target:GetMaxHealth()
			if maxHp <= 0 then maxHp = 100 end

			if target:Health() < maxHp then
				local healAmount = isUber and 4 or 2
				target:SetHealth(math.min(maxHp, target:Health() + healAmount))
			end
			self.NextHealTick = curTime + 0.15
		end

		local curCharge = self:GetNWFloat("MG_UberCharge", 0)
		if not isUber and curCharge < self.UberMax and curTime >= (self.NextUberTick or 0) then
			local chargeGain = (target:Health() < target:GetMaxHealth()) and 1.25 or 0.6
			self:SetNWFloat("MG_UberCharge", math.min(self.UberMax, curCharge + chargeGain))
			self.NextUberTick = curTime + 0.5
		end
	end

	if self.Idle == 0 and (self.IdleTimer or 0) <= curTime then
		self:SendWeaponAnim(ACT_VM_IDLE)
		self.Idle = 1
	end
end

function SWEP:OnRemove()
	timer.Remove("TF2_MedigunHealLoop" .. self:EntIndex())
	self:StopChargedSound()

	if CLIENT then
		self:StopClientBeam()
		self:StopChargeEffect()
		return
	end

	if self:GetNWBool("MG_UberActive", false) then
		self:EndUberCharge()
	end
	self:StopHealing()
	self:RestoreOwnerSpeed()
end

-- Смерть/уход игрока: снять убер-неуязвимость и вернуть скорость.
function SWEP:OnOwnerDied()
	if not SERVER then return end
	if self:GetNWBool("MG_UberActive", false) then
		self:EndUberCharge()
	end
	self:StopHealing()
	self:RestoreOwnerSpeed()
end

if SERVER then
	hook.Add("EntityTakeDamage", "TF2_Medigun_UberProtection", function(target, dmginfo)
		if IsValid(target) and target.MG_UberProtected then
			return true
		end
	end)

	hook.Add("PlayerDeath", "TF2_Medigun_CleanupOnDeath", function(ply)
		if not IsValid(ply) then return end

		for _, wep in ipairs(ply:GetWeapons() or {}) do
			if IsValid(wep) and wep.GetClass and wep:GetClass() == "weapon_tf2_medigun" then
				wep:OnOwnerDied()
			end
		end
	end)
end

if CLIENT then
	function SWEP:DrawHUD()
		local owner = self:GetOwner()
		if not IsValid(owner) then return end

		local x, y
		if owner == LocalPlayer() and owner:ShouldDrawLocalPlayer() then
			local trace = util.TraceLine(util.GetPlayerTrace(owner))
			local coords = trace.HitPos:ToScreen()
			x, y = coords.x, coords.y
		else
			x, y = ScrW() / 2, ScrH() / 2
		end

		surface.SetTexture(MG_CrosshairTexture or surface.GetTextureID("sprites/crosshair_4"))
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(x - 16, y - 16, 32, 32)

		local isHealing = self:GetNWBool("MG_Healing", false)
		local target = self:GetNWEntity("MG_HealTarget", NULL)
		local uberActive = self:GetNWBool("MG_UberActive", false)
		local uberCharge = self:GetNWFloat("MG_UberCharge", 0)
		local uberEndTime = self:GetNWFloat("MG_UberEndTime", 0)

		if isHealing and IsValid(target) then
			local patientX = ScrW() / 2
			local patientY = ScrH() - 260

			local patientName = target:IsPlayer() and target:Nick() or target:GetClass()
			draw.SimpleText("ПАЦИЕНТ: " .. patientName, "MedigunHUDMedium", patientX, patientY, Color(0, 200, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			local hp = math.max(0, target:Health())
			local maxHp = math.max(1, target:GetMaxHealth())
			local hpPct = math.Clamp(hp / maxHp, 0, 1)

			draw.SimpleText("ЗДОРОВЬЕ: " .. hp .. " / " .. maxHp .. " (" .. math.Round(hpPct * 100) .. "%)", "MedigunHUDSmall", patientX, patientY + 24, Color(0, 255, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			local barW, barH = 280, 18
			local barX, barY = patientX - barW / 2, patientY + 42

			surface.SetDrawColor(0, 0, 0, 200)
			surface.DrawRect(barX - 2, barY - 2, barW + 4, barH + 4)

			local hpColor = hpPct > 0.7 and Color(0, 255, 0, 220) or (hpPct > 0.3 and Color(255, 255, 0, 220) or Color(255, 50, 50, 220))
			surface.SetDrawColor(hpColor)
			surface.DrawRect(barX, barY, barW * hpPct, barH)

			if uberActive then
				local flashAlpha = math.abs(math.sin(CurTime() * 8)) * 127 + 128
				draw.SimpleText("УБЕР-ЛЕЧЕНИЕ АКТИВНО", "MedigunHUDMedium", patientX, barY + barH + 20, Color(255, 255, 0, flashAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		else
			local patientY = ScrH() - 260
			draw.SimpleText("ЦЕЛЬ: НЕТ", "MedigunHUDMedium", ScrW() / 2, patientY, Color(150, 150, 150, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("Зажмите ЛКМ для лечения цели", "MedigunHUDSmall", ScrW() / 2, patientY + 24, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		local uberW, uberH = 260, 24
		local uberX, uberY = ScrW() / 2 - uberW / 2, ScrH() - 60

		surface.SetDrawColor(0, 0, 0, 220)
		surface.DrawRect(uberX - 3, uberY - 3, uberW + 6, uberH + 6)

		local fillPct = uberActive and math.Clamp((uberEndTime - CurTime()) / self.UberDuration, 0, 1) or (uberCharge / self.UberMax)
		if uberActive then
			surface.SetDrawColor(255, 255, 0, math.abs(math.sin(CurTime() * 10)) * 150 + 105)
		else
			surface.SetDrawColor(0, 255, 100, 220)
		end
		surface.DrawRect(uberX, uberY, uberW * fillPct, uberH)

		local uberText = uberActive and ("УБЕР-ЗАРЯД: " .. string.format("%.1f", math.max(0, uberEndTime - CurTime())) .. " сек") or ("УБЕР-ЗАРЯД: " .. math.Round(uberCharge) .. "%")
		draw.SimpleText(uberText, "MedigunHUDMedium", ScrW() / 2, uberY - 18, uberActive and Color(255, 255, 0, 255) or Color(0, 255, 100, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		if uberCharge >= self.UberMax and not uberActive then
			local readyAlpha = math.abs(math.sin(CurTime() * 5)) * 127 + 128
			draw.SimpleText("ГОТОВ! НАЖМИТЕ ПКМ", "MedigunHUDMedium", ScrW() / 2, uberY + uberH + 16, Color(255, 255, 0, readyAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end
