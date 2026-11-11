@isTest
private class TriggerHandler_Test {

  private static final String TRIGGER_CONTEXT_ERROR = 'Trigger handler called outside of Trigger execution';

  private static String lastMethodCalled;

  private static TriggerHandler_Test.TestHandler handler;

  static {
    handler = new TriggerHandler_Test.TestHandler();
    // override its internal trigger detection
    handler.isTriggerExecuting = true;
    // handlers without a metadata record are inactive
    handler.handlerTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true);
  }

  /***************************************
   * unit tests
   ***************************************/

  // contexts tests

  @isTest
  static void testBeforeInsert() {
    beforeInsertMode();
    handler.run();
    System.assertEquals('beforeInsert', lastMethodCalled, 'last method should be beforeInsert');
  }

  @isTest
  static void testBeforeUpdate() {
    beforeUpdateMode();
    handler.run();
    System.assertEquals('beforeUpdate', lastMethodCalled, 'last method should be beforeUpdate');
  }

  @isTest
  static void testBeforeDelete() {
    beforeDeleteMode();
    handler.run();
    System.assertEquals('beforeDelete', lastMethodCalled, 'last method should be beforeDelete');
  }

  @isTest
  static void testAfterInsert() {
    afterInsertMode();
    handler.run();
    System.assertEquals('afterInsert', lastMethodCalled, 'last method should be afterInsert');
  }

  @isTest
  static void testAfterUpdate() {
    afterUpdateMode();
    handler.run();
    System.assertEquals('afterUpdate', lastMethodCalled, 'last method should be afterUpdate');
  }

  @isTest
  static void testAfterDelete() {
    afterDeleteMode();
    handler.run();
    System.assertEquals('afterDelete', lastMethodCalled, 'last method should be afterDelete');
  }

  @isTest
  static void testAfterUndelete() {
    afterUndeleteMode();
    handler.run();
    System.assertEquals('afterUndelete', lastMethodCalled, 'last method should be afterUndelete');
  }

  @isTest 
  static void testNonTriggerContext() {
    try{
      handler.run();
      System.assert(false, 'the handler ran but should have thrown');
    } catch(TriggerHandler.TriggerHandlerException te) {
      System.assertEquals(TRIGGER_CONTEXT_ERROR, te.getMessage(), 'the exception message should match');
    } catch(Exception e) {
      System.assert(false, 'the exception thrown was not expected: ' + e.getTypeName() + ': ' + e.getMessage());
    }
  }

  // test bypass api

  @isTest
  static void testBypassAPI() {
    afterUpdateMode();

    // test a bypass and run handler
    TriggerHandler.bypass('TestHandler');
    handler.run();
    System.assertEquals(null, lastMethodCalled, 'last method should be null when bypassed');
    System.assertEquals(true, TriggerHandler.isBypassed('TestHandler'), 'test handler should be bypassed');
    resetTest();

    // clear that bypass and run handler
    TriggerHandler.clearBypass('TestHandler');
    handler.run();
    System.assertEquals('afterUpdate', lastMethodCalled, 'last method called should be afterUpdate');
    System.assertEquals(false, TriggerHandler.isBypassed('TestHandler'), 'test handler should be bypassed');
    resetTest();

    // test a re-bypass and run handler
    TriggerHandler.bypass('TestHandler');
    handler.run();
    System.assertEquals(null, lastMethodCalled, 'last method should be null when bypassed');
    System.assertEquals(true, TriggerHandler.isBypassed('TestHandler'), 'test handler should be bypassed');
    resetTest();

    // clear all bypasses and run handler
    TriggerHandler.clearAllBypasses();
    handler.run();
    System.assertEquals('afterUpdate', lastMethodCalled, 'last method called should be afterUpdate');
    System.assertEquals(false, TriggerHandler.isBypassed('TestHandler'), 'test handler should be bypassed');
    resetTest();
  }

  // instance method tests

  @isTest
  static void testLoopCount() {
    beforeInsertMode();
    
    // set the max loops to 2
    handler.setMaxLoopCount(2);

    // run the handler twice
    handler.run();
    handler.run();

    // clear the tests
    resetTest();

    try {
      // try running it. This should exceed the limit.
      handler.run();
      System.assert(false, 'the handler should throw on the 3rd run when maxloopcount is 3');
    } catch(TriggerHandler.TriggerHandlerException te) {
      // we're expecting to get here
      System.assertEquals(null, lastMethodCalled, 'last method should be null');
    } catch(Exception e) {  
      System.assert(false, 'the exception thrown was not expected: ' + e.getTypeName() + ': ' + e.getMessage());
    }

    // clear the tests
    resetTest();

    // now clear the loop count
    handler.clearMaxLoopCount();

    try {
      // re-run the handler. We shouldn't throw now.
      handler.run();
      System.assertEquals('beforeInsert', lastMethodCalled, 'last method should be beforeInsert');
    } catch(TriggerHandler.TriggerHandlerException te) {
      System.assert(false, 'running the handler after clearing the loop count should not throw');
    } catch(Exception e) {  
      System.assert(false, 'the exception thrown was not expected: ' + e.getTypeName() + ': ' + e.getMessage());
    }
  }

  @isTest
  static void testLoopCountClass() {
    TriggerHandler.LoopCount lc = new TriggerHandler.LoopCount();
    System.assertEquals(5, lc.getMax(), 'max should be five on init');
    System.assertEquals(0, lc.getCount(), 'count should be zero on init');

    lc.increment();
    System.assertEquals(1, lc.getCount(), 'count should be 1');
    System.assertEquals(false, lc.exceeded(), 'should not be exceeded with count of 1');

    lc.increment();
    lc.increment();
    lc.increment();
    lc.increment();
    System.assertEquals(5, lc.getCount(), 'count should be 5');
    System.assertEquals(false, lc.exceeded(), 'should not be exceeded with count of 5');

    lc.increment();
    System.assertEquals(6, lc.getCount(), 'count should be 6');
    System.assertEquals(true, lc.exceeded(), 'should not be exceeded with count of 6');
  }

  // clean error handling tests

  @isTest
  static void testCleanErrorCustomExceptionMessage() {
    Contact record = runCleanErrorHandler('custom');
    System.assertEquals('custom failure', record.getErrors()[0].getMessage(), 'custom exception messages should pass through');
  }

  @isTest
  static void testCleanErrorSystemExceptionIsGeneric() {
    Contact record = runCleanErrorHandler('system');
    String message = record.getErrors()[0].getMessage();
    System.assert(message.startsWith('An unexpected error occurred. Reference: '), 'system exceptions should be generic: ' + message);
    System.assert(!message.contains('NullPointerException'), 'system exception details should be hidden: ' + message);
  }

  @isTest
  static void testCleanErrorDmlExceptionIsUnwrapped() {
    Contact record = runCleanErrorHandler('dml');
    String message = record.getErrors()[0].getMessage();
    System.assert(message.contains('LastName'), 'the DML error message should be kept: ' + message);
    System.assert(!message.contains('Insert failed'), 'the DML exception wrapper should be removed: ' + message);
  }

  @isTest
  static void testCleanErrorLoopCountExceeded() {
    CleanErrorHandler h = new CleanErrorHandler('none');
    h.setTriggerContext('before insert', true);
    h.setMaxLoopCount(0);
    Contact record = new Contact();
    h.triggerRecords = new List<SObject>{ record };

    h.run();

    System.assert(record.getErrors()[0].getMessage().startsWith('Maximum loop count of 0 reached'), 'loop count errors should be added cleanly');
  }

  @isTest
  static void testCleanErrorWithoutRecords() {
    CleanErrorHandler h = new CleanErrorHandler('system');
    h.setTriggerContext('before insert', true);

    h.run();

    System.assertEquals(0, h.triggerRecords.size(), 'no records should be available outside a trigger');
  }

  // error logger tests

  @isTest
  static void testErrorLoggerReceivesCleanError() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.errorLogger = spy;

    Contact record = runCleanErrorHandler('custom');

    System.assertEquals(1, spy.errors.size(), 'the error should be logged once');
    TriggerHandler.TriggerError error = spy.errors[0];
    System.assertEquals('CleanErrorHandler', error.handlerName, 'the handler name should be logged');
    System.assertEquals('BEFORE_INSERT', error.operation, 'the trigger operation should be logged');
    System.assertEquals(Request.getCurrent().getRequestId(), error.referenceId, 'the request id should be the reference');
    System.assertEquals('custom failure', error.cause.getMessage(), 'the original exception should be logged');
    System.assertEquals(true, error.handledCleanly, 'the error should be marked as handled cleanly');
    System.assertEquals(record.getErrors()[0].getMessage(), error.userMessage, 'the logged user message should match the record error');
    System.assertEquals(new List<SObject>{ record }, error.records, 'the failing records should be logged');
  }

  @isTest
  static void testErrorLoggerReceivesRethrownError() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.errorLogger = spy;
    CleanErrorHandler h = new CleanErrorHandler('custom', false);
    h.setTriggerContext('before insert', true);

    try {
      h.run();
      System.assert(false, 'the handler should rethrow when errors are not handled cleanly');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assertEquals('custom failure', e.getMessage(), 'the original exception should be rethrown');
    }

    System.assertEquals(1, spy.errors.size(), 'the rethrown error should be logged once');
    System.assertEquals(false, spy.errors[0].handledCleanly, 'the error should not be marked as handled cleanly');
    System.assertEquals(null, spy.errors[0].userMessage, 'no user message should be logged for rethrown errors');
  }

  @isTest
  static void testFailingErrorLoggerDoesNotMaskCleanError() {
    TriggerHandler.errorLogger = new FailingLogger();

    Contact record = runCleanErrorHandler('custom');

    System.assertEquals('custom failure', record.getErrors()[0].getMessage(), 'the original error should still reach the record');
  }

  @isTest
  static void testFailingErrorLoggerDoesNotMaskRethrownError() {
    TriggerHandler.errorLogger = new FailingLogger();
    CleanErrorHandler h = new CleanErrorHandler('custom', false);
    h.setTriggerContext('before insert', true);

    try {
      h.run();
      System.assert(false, 'the handler should rethrow when errors are not handled cleanly');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assertEquals('custom failure', e.getMessage(), 'the original exception should be rethrown, not the logger failure');
    }
  }

  @isTest
  static void testLoggersDefaultToDebugLogger() {
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true);

    System.assert(TriggerHandler.errorLogger instanceof TriggerHandler.DebugLogger, 'a blank setting should use the debug error logger');
    System.assert(TriggerHandler.operationLogger instanceof TriggerHandler.DebugLogger, 'a blank setting should use the debug operation logger');
  }

  @isTest
  static void testLoggersResolvedFromSetting() {
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(
      isActive__c = true, Logger__c = 'TriggerHandler.DebugLogger'
    );

    System.assert(TriggerHandler.errorLogger instanceof TriggerHandler.DebugLogger, 'the configured class should log errors');
    System.assert((Object) TriggerHandler.operationLogger === (Object) TriggerHandler.errorLogger, 'one instance should serve both interfaces');
  }

  @isTest
  static void testUnknownLoggerFallsBackToDebugLog() {
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(
      isActive__c = true, Logger__c = 'NoSuchLogger'
    );

    try {
      TriggerHandler.ErrorLogger unused = TriggerHandler.errorLogger;
      System.assert(false, 'an unknown logger class should throw');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assertEquals('Logger class not found: NoSuchLogger', e.getMessage(), 'the missing class should be named');
    }

    Contact record = runCleanErrorHandler('custom');
    System.assertEquals('custom failure', record.getErrors()[0].getMessage(), 'a misconfigured logger should not block clean errors');
  }

  @isTest
  static void testLoggerMustImplementAnInterface() {
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(
      isActive__c = true, Logger__c = 'TriggerHandler'
    );

    try {
      TriggerHandler.OperationLogger unused = TriggerHandler.operationLogger;
      System.assert(false, 'a class implementing neither interface should throw');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assert(e.getMessage().startsWith('TriggerHandler must implement'), 'the misconfigured class should be named: ' + e.getMessage());
    }
  }

  // operation logger tests

  @isTest
  static void testOperationLoggingOffByDefault() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true);
    beforeInsertMode();

    handler.run();

    System.assertEquals('beforeInsert', lastMethodCalled, 'the handler should still run');
    System.assertEquals(0, spy.runs.size(), 'runs should not be logged unless enabled');
  }

  @isTest
  static void testOperationLoggingEnabledGlobally() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    beforeInsertMode();

    handler.run();

    System.assertEquals(1, spy.runs.size(), 'the run should be logged once');
    TriggerHandler.TriggerRun run = spy.runs[0];
    System.assertEquals('TestHandler', run.handlerName, 'the handler name should be logged');
    System.assertEquals('BEFORE_INSERT', run.operation, 'the trigger operation should be logged');
    System.assertEquals(Request.getCurrent().getRequestId(), run.referenceId, 'the request id should be the reference');
    System.assertEquals(true, run.succeeded, 'the run should be marked as succeeded');
    System.assertEquals(null, run.error, 'a successful run should have no error');
    System.assert(run.durationMs >= 0, 'the duration should be measured');
    System.assert(run.cpuTimeMs >= 0, 'the CPU time should be measured');
  }

  @isTest
  static void testOperationLoggingEnabledPerHandler() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true);
    handler.handlerTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    afterUpdateMode();

    handler.run();

    System.assertEquals(1, spy.runs.size(), 'the handler setting should enable logging for its runs');
    System.assertEquals('AFTER_UPDATE', spy.runs[0].operation, 'the trigger operation should be logged');
  }

  @isTest
  static void testOperationLoggingSkipsBypassedHandlers() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    TriggerHandler.bypass('TestHandler');
    beforeInsertMode();

    handler.run();

    System.assertEquals(0, spy.runs.size(), 'bypassed handlers do not run and should not be logged');
  }

  @isTest
  static void testOperationLoggerReceivesCleanFailure() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.errorLogger = spy;
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);

    runCleanErrorHandler('custom');

    System.assertEquals(1, spy.runs.size(), 'the failed run should be logged once');
    System.assertEquals(false, spy.runs[0].succeeded, 'the run should be marked as failed');
    System.assert(spy.runs[0].error === spy.errors[0], 'the run should carry the logged error');
  }

  @isTest
  static void testOperationLoggerReceivesRethrownFailure() {
    SpyLogger spy = new SpyLogger();
    TriggerHandler.operationLogger = spy;
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    CleanErrorHandler h = new CleanErrorHandler('custom', false);
    h.setTriggerContext('before insert', true);

    try {
      h.run();
      System.assert(false, 'the handler should rethrow when errors are not handled cleanly');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assertEquals('custom failure', e.getMessage(), 'the original exception should be rethrown');
    }

    System.assertEquals(1, spy.runs.size(), 'the rethrown run should be logged once');
    System.assertEquals(false, spy.runs[0].error.handledCleanly, 'the run error should be marked as rethrown');
  }

  @isTest
  static void testFailingOperationLoggerDoesNotBreakRun() {
    TriggerHandler.operationLogger = new FailingLogger();
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    beforeInsertMode();

    handler.run();

    System.assertEquals('beforeInsert', lastMethodCalled, 'the handler should run despite the logger failure');
  }

  @isTest
  static void testFailingOperationLoggerDoesNotMaskRethrownError() {
    TriggerHandler.errorLogger = new FailingLogger();
    TriggerHandler.operationLogger = new FailingLogger();
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    CleanErrorHandler h = new CleanErrorHandler('custom', false);
    h.setTriggerContext('before insert', true);

    try {
      h.run();
      System.assert(false, 'the handler should rethrow when errors are not handled cleanly');
    } catch(TriggerHandler.TriggerHandlerException e) {
      System.assertEquals('custom failure', e.getMessage(), 'the original exception should be rethrown, not the logger failure');
    }
  }

  @isTest
  static void testDebugLoggerLogsRun() {
    TriggerHandler.operationLogger = new TriggerHandler.DebugLogger();
    TriggerHandler.globalTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true, Log_Operations__c = true);
    beforeInsertMode();

    handler.run();

    System.assertEquals('beforeInsert', lastMethodCalled, 'the handler should run with the debug logger');
  }

  @isTest
  static void testTriggerErrorRecordIds() {
    Id contactId = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    TriggerHandler.TriggerError error = new TriggerHandler.TriggerError(
      new TriggerHandler.TriggerHandlerException('failure'), 'Handler', 'AFTER_INSERT', 'ref',
      new List<SObject>{ new Contact(Id = contactId), new Contact() }, true, 'failure'
    );

    System.assertEquals(new Set<Id>{ contactId }, error.getRecordIds(), 'only saved record ids should be returned');
  }

  @isTest
  static void testTriggerRunRecordIds() {
    Id contactId = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    TriggerHandler.TriggerRun run = new TriggerHandler.TriggerRun(
      'Handler', 'AFTER_INSERT', 'ref', new List<SObject>{ new Contact(Id = contactId), new Contact() }, 5, 3, null
    );

    System.assertEquals(new Set<Id>{ contactId }, run.getRecordIds(), 'only saved record ids should be returned');
    System.assertEquals(true, run.succeeded, 'a run without an error should be marked as succeeded');
  }

  // private method tests

  @isTest 
  static void testGetHandlerName() {
    System.assertEquals('TestHandler', handler.getHandlerName(), 'handler name should match class name');
  }

  // test virtual methods
  
  @isTest
  static void testVirtualMethods() {
    TriggerHandler h = new TriggerHandler();
    h.beforeInsert();
    h.beforeUpdate();
    h.beforeDelete();
    h.afterInsert();
    h.afterUpdate();
    h.afterDelete();
    h.afterUndelete();
  }

  /***************************************
   * testing utilities
   ***************************************/

  private static void resetTest() {
    lastMethodCalled = null;
  }

  private static Contact runCleanErrorHandler(String failureMode) {
    CleanErrorHandler h = new CleanErrorHandler(failureMode);
    h.setTriggerContext('before insert', true);
    Contact record = new Contact();
    h.triggerRecords = new List<SObject>{ record };

    h.run();

    System.assertEquals(1, record.getErrors().size(), 'the record should have one error');
    return record;
  }

  // modes for testing

  private static void beforeInsertMode() {
    handler.setTriggerContext('before insert', true);
  }

  private static void beforeUpdateMode() {
    handler.setTriggerContext('before update', true);
  }

  private static void beforeDeleteMode() {
    handler.setTriggerContext('before delete', true);
  }

  private static void afterInsertMode() {
    handler.setTriggerContext('after insert', true);
  }

  private static void afterUpdateMode() {
    handler.setTriggerContext('after update', true);
  }

  private static void afterDeleteMode() {
    handler.setTriggerContext('after delete', true);
  }

  private static void afterUndeleteMode() {
    handler.setTriggerContext('after undelete', true);
  }

  // test implementation of the TriggerHandler

  private class TestHandler extends TriggerHandler {

    public override void beforeInsert() {
      TriggerHandler_Test.lastMethodCalled = 'beforeInsert';
    }

    public override void  beforeUpdate() {
      TriggerHandler_Test.lastMethodCalled = 'beforeUpdate';
    }

    public override void beforeDelete() {
      TriggerHandler_Test.lastMethodCalled = 'beforeDelete';
    }

    public override void afterInsert() {
      TriggerHandler_Test.lastMethodCalled = 'afterInsert';
    }

    public override void afterUpdate() {
      TriggerHandler_Test.lastMethodCalled = 'afterUpdate';
    }

    public override void afterDelete() {
      TriggerHandler_Test.lastMethodCalled = 'afterDelete';
    }

    public override void afterUndelete() {
      TriggerHandler_Test.lastMethodCalled = 'afterUndelete';
    }

  }

  // handler that fails in before insert and reports errors cleanly

  private class CleanErrorHandler extends TriggerHandler {
    private String failureMode;
    private Boolean handleCleanly;

    public CleanErrorHandler(String failureMode) {
      this(failureMode, true);
    }

    public CleanErrorHandler(String failureMode, Boolean handleCleanly) {
      this.failureMode = failureMode;
      this.handleCleanly = handleCleanly;
      this.handlerTriggerSetting = new SObject_Trigger_Setting__mdt(isActive__c = true);
    }

    public override Boolean handleErrorsCleanly() {
      return this.handleCleanly;
    }

    public override void beforeInsert() {
      switch on this.failureMode {
        when 'custom' {
          throw new TriggerHandler.TriggerHandlerException('custom failure');
        }
        when 'system' {
          String nothing;
          nothing.length();
        }
        when 'dml' {
          insert new Contact();
        }
      }
    }
  }

  private class SpyLogger implements TriggerHandler.ErrorLogger, TriggerHandler.OperationLogger {
    public List<TriggerHandler.TriggerError> errors = new List<TriggerHandler.TriggerError>();
    public List<TriggerHandler.TriggerRun> runs = new List<TriggerHandler.TriggerRun>();

    public void logError(TriggerHandler.TriggerError error) {
      this.errors.add(error);
    }

    public void logRun(TriggerHandler.TriggerRun run) {
      this.runs.add(run);
    }
  }

  private class FailingLogger implements TriggerHandler.ErrorLogger, TriggerHandler.OperationLogger {
    public void logError(TriggerHandler.TriggerError error) {
      throw new TriggerHandler.TriggerHandlerException('logger failure');
    }

    public void logRun(TriggerHandler.TriggerRun run) {
      throw new TriggerHandler.TriggerHandlerException('logger failure');
    }
  }
	
}
