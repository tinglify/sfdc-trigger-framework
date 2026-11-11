public virtual class TriggerHandler {

  // static map of handlername, times run() was invoked
  private static Map<String, LoopCount> loopCountMap;
  private static Set<String> bypassedHandlers;

  // DML errors with these status codes carry the failing trigger's stack trace in their message
  private static final Set<StatusCode> UNSAFE_DML_STATUS_CODES = new Set<StatusCode>{
    StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY
  };

  // the current context of the trigger, overridable in tests
  @TestVisible
  private TriggerContext context;

  // the current context of the trigger, overridable in tests
  @TestVisible
  private Boolean isTriggerExecuting;

  // static initialization
  static {
    loopCountMap = new Map<String, LoopCount>();
    bypassedHandlers = new Set<String>();
  }

  @TestVisible                                                                                                                                  
  private static Boolean userHasBypassPermission {                                                                                              
      get {                                                                                                                                     
          if(userHasBypassPermission == null){                                                                                                
              userHasBypassPermission = FeatureManagement.checkPermission('Bypass_Apex_Triggers');                                              
          }                                                                                                                                     
          return userHasBypassPermission;
      }                                                                                                                                         
      set;                                                                                                                                    
  }

  @TestVisible 
  private static SObject_Trigger_Setting__mdt globalTriggerSetting {
      get {                                                                                                                                     
          if(globalTriggerSetting == null){
              globalTriggerSetting = SObject_Trigger_Setting__mdt.getInstance('GLOBAL') 
                                     ?? new SObject_Trigger_Setting__mdt(isActive__c = true);                                                                
          }                                                                                                                                     
          return globalTriggerSetting;                                                                                                               
      }                                                                                                                                         
      set;   
  }

  @TestVisible 
  private SObject_Trigger_Setting__mdt handlerTriggerSetting {
      get {                                                                                                                                     
          if(handlerTriggerSetting == null){
              handlerTriggerSetting = SObject_Trigger_Setting__mdt.getInstance(getHandlerName()) 
                                      ?? (SObject_Trigger_Setting__mdt) Type.forName('SObject_Trigger_Setting__mdt').newInstance();
          }
          return handlerTriggerSetting;
      }
      set;
  }

  // one instance per transaction so adapters implementing both interfaces can share state
  private static Object logger {
    get {
      if(logger == null) {
        logger = newLogger(globalTriggerSetting.Logger__c);
      }
      return logger;
    }
    set;
  }

  @TestVisible
  private static ErrorLogger errorLogger {
    get {
      if(errorLogger == null) {
        errorLogger = logger instanceof ErrorLogger ? (ErrorLogger) logger : new DebugLogger();
      }
      return errorLogger;
    }
    set;
  }

  @TestVisible
  private static OperationLogger operationLogger {
    get {
      if(operationLogger == null) {
        operationLogger = logger instanceof OperationLogger ? (OperationLogger) logger : new DebugLogger();
      }
      return operationLogger;
    }
    set;
  }

  // the records in the trigger, overridable in tests
  @TestVisible
  private List<SObject> triggerRecords {
    get {
      if(triggerRecords == null) {
        triggerRecords = Trigger.isExecuting
                       ? (Trigger.isDelete ? Trigger.old : Trigger.new)
                       : new List<SObject>();
      }
      return triggerRecords;
    }
    set;
  }
  
  // constructor
  public TriggerHandler() {
    this.setTriggerContext();
  }

  /***************************************
   * public instance methods
   ***************************************/

  // main method that will be called during execution
  public void run() {

    if(!validateRun()) {
      return;
    }

    String referenceId = Request.getCurrent().getRequestId();
    Long startTime = System.currentTimeMillis();
    Integer startCpuTime = Limits.getCpuTime();
    TriggerError error;

    // dispatch to the correct handler method
    try{
      addToLoopCount();

      switch on this.context {
        when BEFORE_INSERT {
          this.beforeInsert();
        }
        when BEFORE_UPDATE {
          this.beforeUpdate();
        }
        when BEFORE_DELETE {
          this.beforeDelete();
        }
        when AFTER_INSERT {
          this.afterInsert();
        }
        when AFTER_UPDATE {
          this.afterUpdate();
        }
        when AFTER_DELETE {
          this.afterDelete();
        }
        when AFTER_UNDELETE {
          this.afterUndelete();
        }
      }
    }catch(Exception e){
      Boolean handledCleanly = this.handleErrorsCleanly();
      String cleanedErrorMessage = handledCleanly ? this.cleanErrorMessage(e, referenceId) : null;

      error = new TriggerError(
        e, getHandlerName(), this.context.name(), referenceId, this.triggerRecords, handledCleanly, cleanedErrorMessage
      );
      this.safelyLogError(error);

      if (!handledCleanly) {
        throw e;
      }

      for(SObject record : this.triggerRecords){
        record.addError(cleanedErrorMessage);
      }
    }finally{
      if(this.shouldLogOperations()) {
        this.safelyLogRun(new TriggerRun(
          getHandlerName(), this.context.name(), referenceId, this.triggerRecords,
          System.currentTimeMillis() - startTime, Limits.getCpuTime() - startCpuTime, error
        ));
      }
    }
  }

  @TestVisible
  protected virtual Boolean handleErrorsCleanly() { return true; }

  @TestVisible
  protected virtual String cleanErrorMessage(Exception e, String referenceId) {
    String genericMessage = 'An unexpected error occurred. Reference: ' + referenceId;

    if(e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
      DmlException dmlEx = (DmlException) e;
      return UNSAFE_DML_STATUS_CODES.contains(dmlEx.getDmlType(0)) ? genericMessage : dmlEx.getDmlMessage(0);
    }

    if(e.getTypeName().startsWith('System.')) {
      return genericMessage;
    }

    return e.getMessage();
  }

  @TestVisible
  protected virtual void logError(TriggerError error) {
    TriggerHandler.errorLogger.logError(error);
  }

  @TestVisible
  protected virtual void logRun(TriggerRun run) {
    TriggerHandler.operationLogger.logRun(run);
  }

  public void setMaxLoopCount(Integer max) {
    String handlerName = getHandlerName();
    if(!TriggerHandler.loopCountMap.containsKey(handlerName)) {
      TriggerHandler.loopCountMap.put(handlerName, new LoopCount(max));
    } else {
      TriggerHandler.loopCountMap.get(handlerName).setMax(max);
    }
  }

  public void clearMaxLoopCount() {
    this.setMaxLoopCount(-1);
  }

  /***************************************
   * public static methods
   ***************************************/

  public static void bypass(String handlerName) {
    TriggerHandler.bypassedHandlers.add(handlerName);
  }

  public static void clearBypass(String handlerName) {
    TriggerHandler.bypassedHandlers.remove(handlerName);
  }

  public static Boolean isBypassed(String handlerName) {
    return TriggerHandler.bypassedHandlers.contains(handlerName);
  }

  public static void clearAllBypasses() {
    TriggerHandler.bypassedHandlers.clear();
  }

  /***************************************
   * private instancemethods
   ***************************************/

  @TestVisible
  private void setTriggerContext() {
    this.setTriggerContext(null, false);
  }

  @TestVisible
  private void setTriggerContext(String ctx, Boolean testMode) {
    if(!Trigger.isExecuting && !testMode) {
      this.isTriggerExecuting = false;
      return;
    } else {
      this.isTriggerExecuting = true;
    }
    
    if((Trigger.isExecuting && Trigger.isBefore && Trigger.isInsert) ||
        (ctx != null && ctx == 'before insert')) {
      this.context = TriggerContext.BEFORE_INSERT;
    } else if((Trigger.isExecuting && Trigger.isBefore && Trigger.isUpdate) ||
        (ctx != null && ctx == 'before update')){
      this.context = TriggerContext.BEFORE_UPDATE;
    } else if((Trigger.isExecuting && Trigger.isBefore && Trigger.isDelete) ||
        (ctx != null && ctx == 'before delete')) {
      this.context = TriggerContext.BEFORE_DELETE;
    } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isInsert) ||
        (ctx != null && ctx == 'after insert')) {
      this.context = TriggerContext.AFTER_INSERT;
    } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isUpdate) ||
        (ctx != null && ctx == 'after update')) {
      this.context = TriggerContext.AFTER_UPDATE;
    } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isDelete) ||
        (ctx != null && ctx == 'after delete')) {
      this.context = TriggerContext.AFTER_DELETE;
    } else if((Trigger.isExecuting && Trigger.isAfter && Trigger.isUndelete) ||
        (ctx != null && ctx == 'after undelete')) {
      this.context = TriggerContext.AFTER_UNDELETE;
    }
  }

  // increment the loop count
  @TestVisible
  private void addToLoopCount() {
    String handlerName = getHandlerName();
    if(TriggerHandler.loopCountMap.containsKey(handlerName)) {
      Boolean exceeded = TriggerHandler.loopCountMap.get(handlerName).increment();
      if(exceeded) {
        Integer max = TriggerHandler.loopCountMap.get(handlerName).max;
        throw new TriggerHandlerException('Maximum loop count of ' + String.valueOf(max) + ' reached in ' + handlerName);
      }
    }
  }

  // make sure this trigger should continue to run
  @TestVisible
  private Boolean validateRun() {
    if(!this.isTriggerExecuting || this.context == null) {
      throw new TriggerHandlerException('Trigger handler called outside of Trigger execution');
    }

    if(!hasPermissionToRun()){
      return false;
    }

    return !TriggerHandler.bypassedHandlers.contains(getHandlerName());
  }
  
  private Boolean hasPermissionToRun(){
    if(!globalTriggerSetting.isActive__c){
    	return false;
    }
      
    if(!handlerTriggerSetting.isActive__c || userHasBypassPermission){
      	return false;
    }

    return true;
  }

  @TestVisible
  private String getHandlerName() {
    return this.toString().substringBefore(':');
  }

  // a broken logger must never replace the error it was asked to log
  private void safelyLogError(TriggerError error) {
    try {
      this.logError(error);
    } catch(Exception loggingFailure) {
      System.debug(LoggingLevel.ERROR, 'Error logger failed: '
        + loggingFailure.getTypeName() + ': ' + loggingFailure.getMessage());
      new DebugLogger().logError(error);
    }
  }

  private void safelyLogRun(TriggerRun run) {
    try {
      this.logRun(run);
    } catch(Exception loggingFailure) {
      System.debug(LoggingLevel.ERROR, 'Operation logger failed: '
        + loggingFailure.getTypeName() + ': ' + loggingFailure.getMessage());
    }
  }

  private Boolean shouldLogOperations() {
    return globalTriggerSetting.Log_Operations__c == true || handlerTriggerSetting.Log_Operations__c == true;
  }

  private static Object newLogger(String className) {
    if(String.isBlank(className)) {
      return new DebugLogger();
    }

    Type loggerType = Type.forName(className);
    if(loggerType == null) {
      throw new TriggerHandlerException('Logger class not found: ' + className);
    }

    Object instance = loggerType.newInstance();
    if(!(instance instanceof ErrorLogger) && !(instance instanceof OperationLogger)) {
      throw new TriggerHandlerException(className + ' must implement TriggerHandler.ErrorLogger or TriggerHandler.OperationLogger');
    }
    return instance;
  }

  private static Set<Id> recordIdsOf(List<SObject> records) {
    Set<Id> recordIds = new Set<Id>();
    for(SObject record : records) {
      if(record.Id != null) {
        recordIds.add(record.Id);
      }
    }
    return recordIds;
  }

  /***************************************
   * context methods
   ***************************************/

  // context-specific methods for override
  @TestVisible
  protected virtual void beforeInsert(){}
  @TestVisible
  protected virtual void beforeUpdate(){}
  @TestVisible
  protected virtual void beforeDelete(){}
  @TestVisible
  protected virtual void afterInsert(){}
  @TestVisible
  protected virtual void afterUpdate(){}
  @TestVisible
  protected virtual void afterDelete(){}
  @TestVisible
  protected virtual void afterUndelete(){}

  /***************************************
   * inner classes
   ***************************************/

  // inner class for managing the loop count per handler
  @TestVisible
  private class LoopCount {
    private Integer max;
    private Integer count;

    public LoopCount() {
      this.max = 5;
      this.count = 0;
    }

    public LoopCount(Integer max) {
      this.max = max;
      this.count = 0;
    }

    public Boolean increment() {
      this.count++;
      return this.exceeded();
    }

    public Boolean exceeded() {
      return this.max >= 0 && this.count > this.max;
    }

    public Integer getMax() {
      return this.max;
    }

    public Integer getCount() {
      return this.count;
    }

    public void setMax(Integer max) {
      this.max = max;
    }
  }

  // implementations need a public no-arg constructor and are named in SObject_Trigger_Setting__mdt.GLOBAL.Logger__c.
  // records inserted while handling a clean error are rolled back by addError; persist logs with a Publish Immediately platform event instead.
  public interface ErrorLogger {
    void logError(TriggerHandler.TriggerError error);
  }

  // called after every run when Log_Operations__c is checked on the GLOBAL record or the handler's record
  public interface OperationLogger {
    void logRun(TriggerHandler.TriggerRun run);
  }

  public class TriggerError {
    public final Exception cause;
    public final String handlerName;
    // matches System.TriggerOperation names, e.g. BEFORE_INSERT
    public final String operation;
    public final String referenceId;
    public final List<SObject> records;
    // false when the exception is rethrown to the caller
    public final Boolean handledCleanly;
    // the message added to each record, null when not handled cleanly
    public final String userMessage;

    public TriggerError(Exception cause, String handlerName, String operation, String referenceId,
                        List<SObject> records, Boolean handledCleanly, String userMessage) {
      this.cause = cause;
      this.handlerName = handlerName;
      this.operation = operation;
      this.referenceId = referenceId;
      this.records = records ?? new List<SObject>();
      this.handledCleanly = handledCleanly;
      this.userMessage = userMessage;
    }

    public Set<Id> getRecordIds() {
      return recordIdsOf(this.records);
    }
  }

  public class TriggerRun {
    public final String handlerName;
    // matches System.TriggerOperation names, e.g. BEFORE_INSERT
    public final String operation;
    public final String referenceId;
    public final List<SObject> records;
    public final Long durationMs;
    public final Integer cpuTimeMs;
    public final Boolean succeeded;
    // null when the run succeeded
    public final TriggerHandler.TriggerError error;

    public TriggerRun(String handlerName, String operation, String referenceId, List<SObject> records,
                      Long durationMs, Integer cpuTimeMs, TriggerHandler.TriggerError error) {
      this.handlerName = handlerName;
      this.operation = operation;
      this.referenceId = referenceId;
      this.records = records ?? new List<SObject>();
      this.durationMs = durationMs;
      this.cpuTimeMs = cpuTimeMs;
      this.succeeded = error == null;
      this.error = error;
    }

    public Set<Id> getRecordIds() {
      return recordIdsOf(this.records);
    }
  }

  public class DebugLogger implements ErrorLogger, OperationLogger {
    public void logError(TriggerHandler.TriggerError error) {
      System.debug(LoggingLevel.ERROR, error.handlerName + ' failed in ' + error.operation + ' [' + error.referenceId + ']: '
        + error.cause.getTypeName() + ': ' + error.cause.getMessage() + '\n' + error.cause.getStackTraceString());
    }

    public void logRun(TriggerHandler.TriggerRun run) {
      System.debug(LoggingLevel.INFO, run.handlerName + ' ' + run.operation + (run.succeeded ? ' succeeded' : ' failed')
        + ' on ' + run.records.size() + ' records in ' + run.durationMs + 'ms (' + run.cpuTimeMs + 'ms CPU) [' + run.referenceId + ']');
    }
  }

  // possible trigger contexts
  @TestVisible
  private enum TriggerContext {
    BEFORE_INSERT, BEFORE_UPDATE, BEFORE_DELETE,
    AFTER_INSERT, AFTER_UPDATE, AFTER_DELETE,
    AFTER_UNDELETE
  }

  // exception class
  public class TriggerHandlerException extends Exception {}

}