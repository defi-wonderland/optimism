package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"time"
)

func runFoundryRelay() {
	fmt.Println("Starting foundry-relay flow...")

	// Step 1: Run SetupSupersim script to deploy contracts and send message
	fmt.Println("\n=== Step 1: Deploying contracts and sending message ===")
	cmd := exec.Command("forge", "script", "solidity/SendMessages.s.sol:SendMessages", "--broadcast")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		log.Fatalf("SendMessages script failed: %v", err)
	}

	// Wait a bit for the transaction to be mined
	fmt.Println("Waiting for transaction to be mined...")
	time.Sleep(2 * time.Second)

	// Step 2: Run Relay script to relay the message and claim funds
	fmt.Println("\n=== Step 2: Relaying message and testing end state ===")
	cmd = exec.Command("forge", "script", "solidity/RelayMessages.s.sol:RelayMessages", "--broadcast")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		log.Fatalf("Relay script failed: %v", err)
	}

	fmt.Println("\n✅ Relay flow completed successfully!")
}
