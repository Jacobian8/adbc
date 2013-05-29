/*******************************************************************************
 * Copyright (c) 2012-2013 Tim Molderez.
 * 
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the 3-Clause BSD License
 * which accompanies this distribution, and is available at
 * http://www.opensource.org/licenses/BSD-3-Clause
 ******************************************************************************/

package be.ac.ua.ansymo.example_bank;

import be.ac.ua.ansymo.adbc.annotations.ensures;
import be.ac.ua.ansymo.adbc.annotations.requires;


public class SavingsAccount extends Account {
	public SavingsAccount(double amount, User owner) {
		super(amount, owner);
	}
	
	@requires({
		"amount>0",
		"to!=null",
		"$this.getOwner()==to.getOwner()"})
	@ensures({
		"$this.getAmount()==$old($this.getAmount())-amount",
		"to.getAmount()==$old(to.getAmount())+amount"
		})
	public void transfer(double amount, Account to) {
		withdraw(amount);
		to.deposit(amount);
		
	}
}
