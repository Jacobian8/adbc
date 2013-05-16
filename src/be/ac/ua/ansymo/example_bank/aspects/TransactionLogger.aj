package be.ac.ua.ansymo.example_bank.aspects;

import be.ac.ua.ansymo.adbc.annotations.ensures;
import be.ac.ua.ansymo.adbc.annotations.invariant;
import be.ac.ua.ansymo.adbc.annotations.requires;
import be.ac.ua.ansymo.example_bank.Account;

/**
 * Aspect that logs all transfers between accounts
 * @author Tim Molderez
 */
@invariant("true")
public aspect TransactionLogger {
	@requires("true")
	@ensures("true")
	after(double amount, Account to, Account from): call(void Account.transfer(double, Account)) 
	&& args(amount, to) && target(from) {
		System.out.println("TransactionLogger: Starting transfer of " + amount + " bucks " +
				"from " + from.getOwner().getName()	+ " to " + to.getOwner().getName());
	}
}
