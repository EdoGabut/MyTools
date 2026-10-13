local args = {
	buffer.fromstring("\140\001-\000\000\224:=\193\004B\028\005\001\028\v\aItemKey\v\006Trowel\v\005Count\005\255\v\bCategory\v\aTrowels\000\000\000")
}
game:GetService("ReplicatedStorage"):WaitForChild("SharedModules"):WaitForChild("Packet"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
