local args = {
	buffer.fromstring("\140\001+\000\000@\197\002\242\005B\028\005\001\028\v\aItemKey\v\018Cider Watering Can\v\005Count\005\255\v\bCategory\v\fWateringCans\000\000\000")
}
game:GetService("ReplicatedStorage"):WaitForChild("SharedModules"):WaitForChild("Packet"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
