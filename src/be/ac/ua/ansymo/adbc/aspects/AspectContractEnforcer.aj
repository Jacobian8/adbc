/**
 * Copyright (c) 2012 Tim Molderez.
 * 
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the 3-Clause BSD License
 * which accompanies this distribution, and is available at
 * http://www.opensource.org/licenses/BSD-3-Clause
 */

package be.ac.ua.ansymo.adbc.aspects;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.EmptyStackException;
import java.util.Vector;

import javax.script.ScriptException;

import org.aspectj.lang.Aspects;
import org.aspectj.lang.JoinPoint;
import org.aspectj.lang.annotation.AdviceName;
import org.aspectj.lang.reflect.AdviceSignature;
import org.aspectj.lang.reflect.MethodSignature;

import be.ac.ua.ansymo.adbc.AdbcConfig;
import be.ac.ua.ansymo.adbc.annotations.advisedBy;
import be.ac.ua.ansymo.adbc.annotations.ensures;
import be.ac.ua.ansymo.adbc.annotations.invariant;
import be.ac.ua.ansymo.adbc.annotations.pointcutRuntimeTest;
import be.ac.ua.ansymo.adbc.annotations.requires;
import be.ac.ua.ansymo.adbc.exceptions.InvariantException;
import be.ac.ua.ansymo.adbc.exceptions.PostConditionException;
import be.ac.ua.ansymo.adbc.exceptions.PreConditionException;
import be.ac.ua.ansymo.adbc.exceptions.SubstitutionException;
import be.ac.ua.ansymo.adbc.utilities.ContractInterpreter;

/**
 * This aspect enforces the contracts of all aspects in the application. 
 * If a contract is broken, a ContractEnforcementException is thrown.
 * 
 * @author Tim Molderez
 */
public aspect AspectContractEnforcer extends AbstractContractEnforcer {
	private JoinPoint tjp = null;	// The thisjoinpoint object of the user-advice
	private String advKind;			// User-advice kind (before, after around)

	// Contracts of the user-advice
	protected String[] advPre;
	protected String[] advPost;
	protected String[] advInv;

//	private String[] advBySuffix = null;
//	private Vector<String> advByRuntimeTests = null;

	/**
	 * Contract enforcer for advice
	 */
	Object around(Object dyn): adviceexecution() && this(dyn) 
	&& !within(be.ac.ua.ansymo.adbc.aspects.*) && excludeContractEnforcers() {
		/* Very sensitive pointcut! Do not perform any method calls here besides preCheck() and postCheck() 
		 * or you'll trigger infinite pointcut matching! */

		// Retrieve the thisJoinPoint object of the user-advice
		try {
			/* Note that we're peeking into CallStack, not popping! Other contract enforcement
			 * still need this top entry! */
			tjp = CallStack.peek();
		} catch (EmptyStackException e) {
			/* In case the advice we've intercepted advises join points other than calls and executions,
			 * there's not going to be an entry on the CallStack for it..
			 * TODO: For now we don't support these kinds of advice yet.
			 * Still need to figure out some way to get access to the join point they advise.. */
			return proceed(dyn);
		}

		try {
			preCheck(thisJoinPoint, dyn);
			Object result = proceed(dyn);
			if (AdbcConfig.checkPostconditions) {
				postCheck(thisJoinPoint,dyn, result);
			}
			return result;
		} catch (ScriptException e) {
			throw new RuntimeException("Failed to evaluate contract: " + e.getMessage());
		}
	}

	/*
	 * Do the necessary preparation and
	 * check all contracts before advice execution (preconditions, invariants, substitution principle)
	 */
	private void preCheck(JoinPoint jp, Object dyn) throws ScriptException {
		/* ****************************************************************
		 * Fetching the necessary info...
		 **************************************************************** */

		// Retrieve the join point advised by the user-advice 
		tjp = CallStack.peek();

		// Retrieve the method being advised by the user-advice
		String m = tjp.getSignature().toString();
		int lastdot = m.lastIndexOf('.');
		m = m.substring(lastdot + 1, m.length());
		Method mBody = ((MethodSignature) tjp.getSignature()).getMethod();

		// Retrieve the user-advice
		AdviceSignature aSig = (AdviceSignature) (jp.getSignature());
		Method aBody = aSig.getAdvice();

		// Determine whether this advice is mentioned in an @advisedBy clause. And if so, which advice follow in that clause?
		String[] advBySuffix = isAdvisedBy(mBody, aBody, tjp.getKind());
		boolean isAdvisedBy = advBySuffix != null;

		// Get the contracts of the user-advice's advised joinpoint
		// TODO: This currently does not work yet for higher-order advice..
		pre = new String[]{"true"};
		post = new String[]{"true"};
		inv = new String[]{"true"};

		if (mBody.isAnnotationPresent(requires.class)) {
			pre = mBody.getAnnotation(requires.class).value();
		}
		if (mBody.isAnnotationPresent(ensures.class)) {
			post = mBody.getAnnotation(ensures.class).value();
		}
		if (tjp.getTarget()!=null && tjp.getTarget().getClass().isAnnotationPresent(invariant.class)) {
			inv = tjp.getTarget().getClass().getAnnotation(invariant.class).value();
		}

		// Get the contracts of the user-advice itself
		advPre = new String[]{"true"};
		advPost = new String[]{"true"};
		advInv = new String[]{"true"};

		if (AdbcConfig.checkSubstitutionPrinciple || isAdvisedBy) {
			if (aBody.isAnnotationPresent(requires.class)) {
				advPre = aBody.getAnnotation(requires.class).value();
			}
			if (aBody.isAnnotationPresent(ensures.class)) {
				advPost = aBody.getAnnotation(ensures.class).value();
			}
			if (dyn.getClass().isAnnotationPresent(invariant.class)) {
				advInv = dyn.getClass().getAnnotation(invariant.class).value();
			}
		}

		// Determine user-advice kind (relying on its internal method name)
		advKind = "around";
		if (aSig.getName().contains("$before$")) {
			advKind = "before";
		} else if (aSig.getName().contains("$after$")) {
			advKind = "after";
		}

		/* ****************************************************************
		 * Binding contract variables
		 **************************************************************** */

		// Reset bindings
		ceval = new ContractInterpreter();

		// Resolve the $proc keyword + $this variable binding (of user advice's this object)
		if(isAdvisedBy && advKind.equals("around")) {
			AdvBySuffix suffixInfo = getAdvBySuffixContracts(advBySuffix);
			suffixInfo.aspectInstances.add(0, jp.getThis());
			pre = ceval.evalProc(advPre, pre, suffixInfo.pre, suffixInfo.runtimeTests, suffixInfo.aspectInstances);
			post = ceval.evalProc(advPost, post, suffixInfo.post, suffixInfo.runtimeTests, suffixInfo.aspectInstances);
		} else {
			advPre = ceval.evalProc(advPre, pre, jp.getThis());
			advPost = ceval.evalProc(advPost, post, jp.getThis());
		}
		
		// Bind $this to the advised method's this object
		ceval.setThisBinding(tjp.getTarget());
		
		// Bind parameter values of advised join point and the advice itself
		MethodSignature mSig = (MethodSignature) (tjp.getSignature());
		ceval.setParameterBindings(mSig.getParameterNames(),tjp.getArgs());
		ceval.setParameterBindings(aSig.getParameterNames(),jp.getArgs());

		// Evaluate calls to the $old() function in postconditions of advice
		try {
			if (AdbcConfig.checkPostconditions && !isAdvisedBy && AdbcConfig.checkSubstitutionPrinciple) {
				advPost = ceval.evalOldFunction(advPost);
			}
		} catch (ScriptException e) {
			throw new RuntimeException("Failed to evaluate old() call: " + e.getMessage());
		}

		// Evaluate calls to the $old() function in postconditions of the advised join point
		try {
			if (AdbcConfig.checkPostconditions) {	
				post = ceval.evalOldFunction(post);
			}
		} catch (ScriptException e) {
			throw new RuntimeException("Failed to evaluate old() call: " + e.getMessage());
		}
		
		/* ****************************************************************
		 * Actual contract enforcement
		 **************************************************************** */
		
		// Test preconditions
		if (!advKind.equals("after")) {
			String stPreFailed = ceval.evalContract(pre);
			if (stPreFailed != null) {
				throw new PreConditionException(stPreFailed, getCaller());
			}
		}
		
		// Test invariants
		String invFailed = ceval.evalContract(inv);
		if (invFailed != null) {
			throw new InvariantException(invFailed, getCaller(), "precondition");
		}

		// Test advice substitution (if applicable)
		if (!isAdvisedBy && AdbcConfig.checkSubstitutionPrinciple) {
			ceval.setParameterBindings(aSig.getParameterNames(),jp.getArgs());

			String jpPreFailed = ceval.evalContract(advPre);
			if (jpPreFailed != null) {
				throw new SubstitutionException(jpPreFailed, jp.getSignature().toString(), "precondition too strong");
			}

			invFailed = ceval.evalContract(advInv);
			if (invFailed != null) {
				throw new InvariantException(invFailed, jp.getSignature().toString(), "invariant not preserved");
			}
		}
	}

	/*
	 * Check contracts after advice execution (postconditions, invariants, substitution principle)
	 */
	private void postCheck(JoinPoint jp, Object dyn, Object result) throws ScriptException {
		// Bind the return value
		ceval.setReturnValueBinding(result);

		// Test postconditions
		if (!advKind.equals("before")) {
			String stPostFailed = ceval.evalContract(post);
			if (stPostFailed != null) {
				throw new PostConditionException(stPostFailed, dyn.getClass()
						.toString());
			}
		}

		// Test invariants
		String invFailed = ceval.evalContract(inv);
		if (invFailed != null) {
			throw new InvariantException(invFailed, dyn.getClass().toString(), "postcondition");
		}

		// Test advice substitution
		if (AdbcConfig.checkSubstitutionPrinciple) {
			ceval.setThisBinding(jp.getThis());

			String jpPostFailed = ceval.evalContract(advPost);
			if (jpPostFailed != null) {
				throw new SubstitutionException(jpPostFailed, jp.getSignature()
						.toString(), "postcondition too weak");
			}

			invFailed = ceval.evalContract(advInv);
			if (invFailed != null) {
				throw new InvariantException(invFailed, tjp.getTarget().toString(), "invariant not preserved");
			}
		}
	}

	/*
	 * Given an advice mentioned in an @advisedBy clause, return 
	 * the pre- or postconditions of all advice that follow in that clause
	 * Additionally, the advByRuntimeTests array is filled with the runtime tests of these advice.
	 * 
	 * @param contractKind	"pre" or "post"
	 * @return	the pre-or postconditions of all following advice
	 */
	private AdvBySuffix getAdvBySuffixContracts(String[] advBySuffix) {
		AdvBySuffix result = new AdvBySuffix();
		result.pre = new Vector<String[]>();
		result.post = new Vector<String[]>();
		result.runtimeTests = new Vector<String>();
		result.aspectInstances = new Vector<Object>();
		
		for (String adv : advBySuffix) {
			try {
				int separator = adv.lastIndexOf('.');
				String aspectName = adv.substring(0, separator);
				String adviceName = adv.substring(separator+1, adv.length());

				Class<?> asp = Class.forName(aspectName);
				result.aspectInstances.add(Aspects.aspectOf(asp));
				
				// Find the advice with the name we're looking for
				for (Method adv2 : asp.getMethods()) {
					if(adv2.isAnnotationPresent(AdviceName.class)&& adv2.getAnnotation(AdviceName.class).value().equals(adviceName)) {
						String[] proc = {"$proc"};
						if (adv2.isAnnotationPresent(requires.class)) {
							result.pre.add(adv2.getAnnotation(requires.class).value());
						} else {
							result.pre.add(proc);
						}
						
						if (adv2.isAnnotationPresent(ensures.class)) {
							result.post.add(adv2.getAnnotation(ensures.class).value());
						} else {
							result.post.add(proc);
						} 
						
						if(adv2.isAnnotationPresent(pointcutRuntimeTest.class)) {
							result.runtimeTests.add(adv2.getAnnotation(pointcutRuntimeTest.class).value());
						} else {
							result.runtimeTests.add("true");
						}
					}
				}
			} catch (ClassNotFoundException e) {
				e.printStackTrace();
			}
		}
		return result;
	}
	
	/*
	 * Determine whether advice aBody appears in the advisedBy clause of method mBody (or the same method in an ancestor class)
	 * @param mBody				the method being advised
	 * @param aBody				the user-advice
	 * @param joinpointKind		kind of the advised join point (e.g. "method call")
	 * @return					if the advice is mentioned in an @advisedBy clause, return a list of the advice names that follow
	 * 							; if the advice isn't mentioned, return null
	 */
	private String[] isAdvisedBy(Method mBody, Method aBody, String joinpointKind) {
		// We only allow advice on call join points to be mentioned in @advisedBy clauses
		if (!joinpointKind.equals("method-call")) {
			return null;
		}
		
		// The advice must have a name in order for it to be mentioned..
		if (!aBody.isAnnotationPresent(AdviceName.class)) {
			return null;
		}

		String advName = aBody.getAnnotation(AdviceName.class).value();
		Class<?> mClass = mBody.getDeclaringClass();
		Class<?>[] mParTypes = mBody.getParameterTypes();
		String mName = mBody.getName();

		while(mClass!=null) {
			try {
				mBody = mClass.getMethod(mName, mParTypes);
				// If there's an @advisedBy annotation, go check whether aBody is mentioned..
				if (mBody.isAnnotationPresent(advisedBy.class)) {
					String[] advBy = mBody.getAnnotation(advisedBy.class).value();
					int i=0;
					for (String listedName : advBy) {
						if(listedName.equals(aBody.getDeclaringClass().getCanonicalName() + "." + advName)) {
							return Arrays.copyOfRange(advBy, i+1, advBy.length);
						}
						i++;
					}
				}
			} catch (Exception e) {/* If the method is not found within mClass, do nothing.. */}
			mClass = mClass.getSuperclass();
		}
		return null;
	}

	/*
	 * Retrieve the caller of the user-advice
	 */
	private String getCaller() {
		/* Runtime stack at this point:
		 * 0: getStackTrace()
		 * 1: getCaller()
		 * 2: preCheck()
		 * 3: preCheck()
		 * 4: around (contract enforcer)
		 * 5: user-advice
		 * 6: tjp
		 * 7: caller <== This is what we're interested in..	*/
		StackTraceElement elem = Thread.currentThread().getStackTrace()[7];
		return elem.toString();
	}
	
	// Container for return value of getAdvBySuffixContracts
	private class AdvBySuffix {
		public Vector<String[]> pre;
		public Vector<String[]> post;
		public Vector<String> runtimeTests;
		public Vector<Object> aspectInstances;
	}
}
