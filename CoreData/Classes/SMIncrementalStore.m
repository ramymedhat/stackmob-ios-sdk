/*
 * Copyright 2012-2013 StackMob
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 NOTE: Most of the comments on this page reference Apple's NSIncrementalStore Class Reference.
 */

#import "SMIncrementalStore.h"
#import "StackMob.h"
#import "KeychainWrapper.h"
#import "SMDataStore+Protected.h"
#import "AFHTTPClient.h"
#import "SMIncrementalStoreNode.h"

#define DLog(fmt, ...) NSLog((@"Performing %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#define CACHE_MAP_FILE @"CacheMap.plist"
#define SQL_DB @"CoreDataStore.sqlite"
#define DIRTY_QUEUE_FILE @"DirtyQueue.plist"

NSString *const SMIncrementalStoreType = @"SMIncrementalStore";
NSString *const SM_DataStoreKey = @"SM_DataStoreKey";
NSString *const StackMobRelationsKey = @"X-StackMob-Relations";
NSString *const SerializedDictKey = @"SerializedDict";

NSString *const SMInsertedObjectFailures = @"SMInsertedObjectFailures";
NSString *const SMUpdatedObjectFailures = @"SMUpdatedObjectFailures";
NSString *const SMDeletedObjectFailures = @"SMDeletedObjectFailures";

NSString *const SMFailedManagedObjectID = @"SMFailedManagedObjectID";
NSString *const SMFailedManagedObjectError = @"SMFailedManagedObjectError";

NSString *const SMPurgeObjectFromCacheNotification = @"SMPurgeObjectFromCacheNotification";
NSString *const SMPurgeObjectsFromCacheNotification = @"SMPurgeObjectsFromCacheNotification";
NSString *const SMPurgeObjectsFromCacheByEntityNotification = @"SMPurgeObjectsFromCacheByEntityNotification";
NSString *const SMResetCacheNotification = @"SMResetCacheNotification";

NSString *const SMCachePurgeManagedObjectID = @"SMCachePurgeManagedObjectID";
NSString *const SMCachePurgeArrayOfManageObjectIDs = @"SMCachePurgeArrayOfManageObjectIDs";
NSString *const SMCachePurgeOfObjectsFromEntityName = @"SMCachePurgeOfObjectsFromEntityName";

NSString *const SMThreadDefaultOptions = @"SMThreadDefaultOptions";
NSString *const SMRequestSpecificOptions = @"SMRequestSpecificOptions";

///-------------------------------
/// Internal Constants
///-------------------------------

NSString *const SMFailedRequestError = @"SMFailedRequestError";
NSString *const SMFailedRequestObjectPrimaryKey = @"SMFailedRequestObjectPrimaryKey";
NSString *const SMFailedRequestObjectEntity = @"SMFailedRequestObjectEntity";
NSString *const SMFailedRequest = @"SMFailedRequest";
NSString *const SMFailedRequestOptions = @"SMFailedRequestOptions";
NSString *const SMFailedRequestSuccessBlock = @"SMFailedRequestSuccessBlock";
NSString *const SMFailedRequestFailureBlock = @"SMFailedRequestFailureBlock";
NSString *const SMFailedRequestOriginalSuccessBlock = @"SMFailedRequestOriginalSuccessBlock";
NSString *const ObjectID = @"ObjectID";
NSString *const ObjectEntityName = @"ObjectEntityName";

NSString *const SMFailedRefreshBlock = @"SMFailedRefreshBlock";


BOOL SM_CORE_DATA_DEBUG = NO;
unsigned int SM_MAX_LOG_LENGTH = 10000;

NSString* truncateOutputIfExceedsMaxLogLength(id objectToCheck) {
    return [[NSString stringWithFormat:@"%@", objectToCheck] length] > SM_MAX_LOG_LENGTH ? [[[NSString stringWithFormat:@"%@", objectToCheck] substringToIndex:SM_MAX_LOG_LENGTH] stringByAppendingString:@" <MAX_LOG_LENGTH_REACHED>"] : objectToCheck;
}

@interface SMIncrementalStore () {
    
}

///-------------------------------
/// Properties
///-------------------------------

@property (nonatomic, strong) __block SMCoreDataStore *coreDataStore;
@property (nonatomic, strong) __block NSManagedObjectContext *localManagedObjectContext;
@property (nonatomic, strong) NSPersistentStoreCoordinator *localPersistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectModel *localManagedObjectModel;

// Cache mapping table appears as Key: StackMob object ID, Value:
@property (nonatomic, strong) __block NSMutableDictionary *cacheMappingTable;
// TODO add comments
@property (nonatomic, strong) __block NSMutableDictionary *dirtyQueue;

@property (nonatomic) dispatch_queue_t callbackQueue;

///-------------------------------
/// Saves and Fetches
///-------------------------------

- (id)SM_handleSaveRequest:(NSPersistentStoreRequest *)request
               withContext:(NSManagedObjectContext *)context
                     error:(NSError *__autoreleasing *)error;

// INSERTS
- (BOOL)SM_handleInsertedObjects:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable;
- (BOOL)SM_handleInsertedObjectsWhenOnline:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;
- (BOOL)SM_handleInsertedObjectsWhenOffline:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;

// UPDATES
- (BOOL)SM_handleUpdatedObjects:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable;
- (BOOL)SM_handleUpdatedObjectsWhenOnline:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;
- (BOOL)SM_handleUpdatedObjectsWhenOffline:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;

// DELETES
- (BOOL)SM_handleDeletedObjects:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable;
- (BOOL)SM_handleDeletedObjectsWhenOnline:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;
- (BOOL)SM_handleDeletedObjectsWhenOffline:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;


// FETCHES
- (id)SM_handleFetchRequest:(NSPersistentStoreRequest *)request
                withContext:(NSManagedObjectContext *)context
                      error:(NSError *__autoreleasing *)error;

- (id)SM_fetchObjects:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError * __autoreleasing *)error;
- (id)SM_fetchObjectIDs:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error;

- (id)SM_fetchObjectsFromNetwork:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError * __autoreleasing *)error;

- (id)SM_fetchObjectsFromCache:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error;

///-------------------------------
/// Cache Configuration
///-------------------------------

- (void)SM_configureCache;
- (NSURL *)SM_getStoreURLForFileComponent:(NSString *)fileComponent;
- (void)SM_createStoreURLPathIfNeeded:(NSURL *)storeURL;

- (void)SM_saveCacheMap;
- (void)SM_readCacheMap;

- (void)SM_readDirtyQueue;
- (void)SM_saveDirtyQueue;

///-------------------------------
/// New Values For Relationship
///-------------------------------

- (id)SM_newValueForRelationship:(NSRelationshipDescription *)relationship
                 forObjectWithID:(NSManagedObjectID *)objectID
                     withContext:(NSManagedObjectContext *)context
                           error:(NSError *__autoreleasing *)error;

///-------------------------------
/// Retrieving Objects
///-------------------------------

- (NSDictionary *)SM_retrieveObjectWithID:(NSString *)objectID entity:(NSEntityDescription *)entity options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error;

- (NSDictionary *)SM_retrieveAndSerializeObjectWithID:(NSString *)objectID entity:(NSEntityDescription *)entity options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context includeRelationships:(BOOL)includeRelationships cacheResult:(BOOL)shouldCache error:(NSError *__autoreleasing*)error;

- (id)SM_retrieveRelatedObjectForRelationship:(NSRelationshipDescription *)relationship parentObject:(NSManagedObject *)parentObject referenceID:(NSString *)referenceID options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error;

- (id)SM_retrieveAndCacheRelatedObjectForRelationship:(NSRelationshipDescription *)relationship parentObject:(NSManagedObject *)parentObject referenceID:(NSString *)referenceID options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error;

///-------------------------------
/// Caching Objects
///-------------------------------

- (void)SM_cacheObjectWithID:(NSString *)objectID values:(NSDictionary *)values entity:(NSEntityDescription *)entity context:(NSManagedObjectContext *)context;
- (NSManagedObjectID *)SM_retrieveCacheObjectForRemoteID:(NSString *)remoteID entityName:(NSString *)entityName createIfNeeded:(BOOL)createIfNeeded;
- (void)SM_populateManagedObject:(NSManagedObject *)object withDictionary:(NSDictionary *)dictionary entity:(NSEntityDescription *)entity;
- (void)SM_populateCacheManagedObject:(NSManagedObject *)object withDictionary:(NSDictionary *)dictionary entity:(NSEntityDescription *)entity;

- (BOOL)SM_saveCache:(NSError *__autoreleasing*)error;

- (NSString *)SM_getRemoteIDForCacheManagedObjectID:(NSManagedObjectID *)cacheManagedObjectID;

///-------------------------------
/// Purging from the Cache
///-------------------------------

- (void)SM_didRecievePurgeObjectFromCacheNotification:(NSNotification *)notification;
- (void)SM_didRecievePurgeObjectsFromCacheNotification:(NSNotification *)notification;
- (void)SM_didRecievePurgeObjectFromCacheByEntityNotification:(NSNotification *)notification;
- (void)SM_didRecieveCacheResetNotification:(NSNotification *)notification;

- (BOOL)SM_purgeObjectsFromCacheByStackMobIDInfo:(NSArray *)arrayOfStackMobObjectIDInfo;
- (BOOL)SM_purgeCacheManagedObjectsFromCache:(NSArray *)arrayOfManagedObjects;
- (BOOL)SM_purgeObjectFromCacheWithStackMobIDInfo:(NSDictionary *)objectInfo error:(NSError *__autoreleasing*)error;
- (BOOL)SM_purgeCacheManagedObjectFromCache:(NSManagedObject *)object;

///-------------------------------
/// Operational Methods
///-------------------------------

- (void)SM_enqueueOperations:(NSArray *)ops dispatchGroup:(dispatch_group_t)group completionBlockQueue:(dispatch_queue_t)queue secure:(BOOL)isSecure;

- (BOOL)SM_setErrorAndUserInfoWithFailedOperations:(NSMutableArray *)failedOperations errorCode:(int)errorCode error:(NSError *__autoreleasing*)error;

- (void)SM_waitForRefreshingWithTimeout:(int)timeout;

- (BOOL)SM_doTokenRefreshIfNeededWithGroup:(dispatch_group_t)group queue:(dispatch_queue_t)queue  options:(SMRequestOptions *)options error:(NSError *__autoreleasing*)error;

- (BOOL)SM_enqueueRegularOperations:(NSMutableArray *)regularOperations secureOperations:(NSMutableArray *)secureOperations withGroup:(dispatch_group_t)group queue:(dispatch_queue_t)queue options:(SMRequestOptions *)options refreshAndRetryUnauthorizedRequests:(NSMutableArray *)failedRequestsWithUnauthorizedResponse failedRequests:(NSMutableArray *)failedRequests error:(NSError *__autoreleasing*)error;

///-------------------------------
/// Misc
///-------------------------------

- (NSString *)SM_remoteKeyForEntityName:(NSString *)entityName;
- (NSDictionary *)SM_responseSerializationForDictionary:(NSDictionary *)theObject schemaEntityDescription:(NSEntityDescription *)entityDescription managedObjectContext:(NSManagedObjectContext *)context includeRelationships:(BOOL)includeRelationships;
- (BOOL)SM_addPasswordToSerializedDictionary:(NSDictionary **)originalDictionary originalObject:(SMUserManagedObject *)object;

///-------------------------------
/// Notifications
///-------------------------------

- (void)SM_handleWillSave:(NSNotification *)notification;
- (void)SM_handleDidSave:(NSNotification *)notification;

- (void)SM_registerForNotifications;
- (void)SM_unregisterForNotifications;

@property (nonatomic) BOOL isSaving;

@end

@implementation SMIncrementalStore

@synthesize coreDataStore = _coreDataStore;
@synthesize localManagedObjectModel = _localManagedObjectModel;
@synthesize localManagedObjectContext = _localManagedObjectContext;
@synthesize localPersistentStoreCoordinator = _localPersistentStoreCoordinator;
@synthesize cacheMappingTable = _cacheMappingTable;
@synthesize dirtyQueue = _dirtyQueue;
@synthesize callbackQueue = _callbackQueue;
@synthesize isSaving = _isSaving;

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options {
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options];
    if (self) {
        _coreDataStore = [options objectForKey:SM_DataStoreKey];
        _callbackQueue = dispatch_queue_create("Queue For Incremental Store Request Callbacks", NULL);
        
        self.isSaving = NO;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextWillSaveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_handleWillSave:) name:NSManagedObjectContextWillSaveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_handleDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
        
        if (SM_CACHE_ENABLED) {
            [self SM_unregisterForNotifications];
            [self SM_registerForNotifications];
            [self SM_configureCache];
        }
        
        if (SM_CORE_DATA_DEBUG) {DLog(@"STACKMOB SYSTEM UPDATE: Incremental Store initialized and ready to go.")}
    }
    return self;
}

- (void)dealloc
{
    [self SM_unregisterForNotifications];
}

- (void)SM_registerForNotifications
{
    
    // Cache Purge Notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_didRecievePurgeObjectFromCacheNotification:) name:SMPurgeObjectFromCacheNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_didRecievePurgeObjectsFromCacheNotification:) name:SMPurgeObjectsFromCacheNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_didRecievePurgeObjectFromCacheByEntityNotification:) name:SMPurgeObjectsFromCacheByEntityNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SM_didRecieveCacheResetNotification:) name:SMResetCacheNotification object:self.coreDataStore];
    
    
}

- (void)SM_unregisterForNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SMPurgeObjectFromCacheNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SMPurgeObjectsFromCacheNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SMPurgeObjectsFromCacheByEntityNotification object:self.coreDataStore];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SMResetCacheNotification object:self.coreDataStore];
    
}

- (void)SM_handleWillSave:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    if ([[notification object] persistentStoreCoordinator] == [self.coreDataStore persistentStoreCoordinator]) {
        if (SM_CORE_DATA_DEBUG) {DLog(@"Updating isSaving to YES")}
        self.isSaving = YES;
    }
}

- (void)SM_handleDidSave:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    if ([[notification object] persistentStoreCoordinator] == [self.coreDataStore persistentStoreCoordinator]) {
        if (SM_CORE_DATA_DEBUG) {DLog(@"Updating isSaving to NO")}
        self.isSaving = NO;
    }
}

/*
 Once a store has been created, the persistent store coordinator invokes loadMetadata: on it. In your implementation, if all goes well you should typically load the store metadata, call setMetadata: to store the metadata, and return YES. If an error occurs, however (if the store is invalid for some reason—for example, if the store URL is invalid, or the user doesn’t have read permission for the store URL), create an NSError object that describes the problem, assign it to the error parameter passed into the method, and return NO.
 
 In the specific case where the store is new, you may choose not to generate metadata in loadMetadata:, but instead allow it to be automatically generated. In this case, the call to setMetadata: is not necessary.
 
 If the metadata is generated automatically, the store identifier will set to a generated UUID. To override this automatic UUID generation, override identifierForNewStoreAtURL: to return an appropriate value. Store identifiers should either be persisted as part of the store metadata, or uniquely derivable in some way such that a given store will have the same identifier even if added to multiple persistent store coordinators. The identifier may be any type of object, although if you want object IDs created by your store to respond to URIRepresentation or for managedObjectIDForURIRepresentation: to be able to parse the generated URI representation, it should be an instance of NSString.
 
 Note: loadMetadata: should ignore any potential skew between the store and the model in use by the coordinator; this will bee handled automatically by the persistent store coordinator later. It is sufficient to return the version hashes that were saved in the store metadata the last time the store was saved (if the store is new the version hashes for the current model in use should be returned).
 
 In your implementation of this method, you must validate that the URL used to create the store is usable (the location exists and if necessary is writable, the schema is compatible, and so on) and return an error if there is an issue.
 
 */
- (BOOL)loadMetadata:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSString* uuid = [[NSProcessInfo processInfo] globallyUniqueString];
    [self setMetadata:[NSDictionary dictionaryWithObjectsAndKeys:
                       SMIncrementalStoreType, NSStoreTypeKey,
                       uuid, NSStoreUUIDKey,
                       @"Something user defined", @"Some user defined key",
                       nil]];
    return YES;
}

/*
 Return Value
 A value as appropriate for request, or nil if the request cannot be completed
 
 Discussion
 The value to return depends on the result type (see resultType) of request:
 
 You should implement this method conservatively, and expect that unknown request types may at some point be passed to the method. The correct behavior in these cases is to return nil and an error.
 */

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    id result = nil;
    switch (request.requestType) {
        case NSSaveRequestType:
            result = [self SM_handleSaveRequest:request withContext:context error:error];
            break;
        case NSFetchRequestType:
            result = [self SM_handleFetchRequest:request withContext:context error:error];
            break;
        default:
            [NSException raise:SMExceptionIncompatibleObject format:@"Unknown request type."];
            break;
    }
    
    //
    // Workaround for gnarly bug.
    //
    // I believe the issue is in NSManagedObjectContext -executeFetchRequest:error:, which seems to be releasing the error object.
    // We work around by manually incrementing the object's retain count.
    //
    // For details, see:
    //
    //   https://devforums.apple.com/message/560644#560644
    //   http://clang.llvm.org/docs/AutomaticReferenceCounting.html#objects.operands.casts
    //   http://developer.apple.com/library/ios/#releasenotes/ObjectiveC/RN-TransitioningToARC
    //
    
    if (result == nil && error != NULL) {
        *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
    }
    
    [self.coreDataStore.globalRequestOptions setTryRefreshToken:YES];
    return result;
}

////////////////////////////
#pragma mark - Save Requests
////////////////////////////

/*
 If the request is a save request, you record the changes provided in the request’s insertedObjects, updatedObjects, and deletedObjects collections. Note there is also a lockedObjects collection; this collection contains objects which were marked as being tracked for optimistic locking (through the detectConflictsForObject:: method); you may choose to respect this or not.
 In the case of a save request containing objects which are to be inserted, executeRequest:withContext:error: is preceded by a call to obtainPermanentIDsForObjects:error:; Core Data will assign the results of this call as the objectIDs for the objects which are to be inserted. Once these IDs have been assigned, they cannot change.
 
 Note that if an empty save request is received by the store, this must be treated as an explicit request to save the metadata, but that store metadata should always be saved if it has been changed since the store was loaded.
 
 If the request is a save request, the method should return an empty array.
 If the save request contains nil values for the inserted/updated/deleted/locked collections; you should treat it as a request to save the store metadata.
 
 @note: We are *IGNORING* locked objects. We are also not handling the metadata save requests, because AFAIK we don't need to generate any.
 */
- (id)SM_handleSaveRequest:(NSPersistentStoreRequest *)request
               withContext:(NSManagedObjectContext *)context
                     error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    SMRequestOptions *options = [threadDictionary objectForKey:SMRequestSpecificOptions];
    if (!options) {
        options = self.coreDataStore.globalRequestOptions;
    }
    
    NSSaveChangesRequest *saveRequest = [[NSSaveChangesRequest alloc] initWithInsertedObjects:[context insertedObjects] updatedObjects:[context updatedObjects] deletedObjects:[context deletedObjects] lockedObjects:nil];
    
    BOOL networkAvailable;
    if (SM_CACHE_ENABLED) {
        networkAvailable = [self SM_checkNetworkAvailability];
    } else {
        networkAvailable = YES;
    }
    
    NSSet *insertedObjects = [saveRequest insertedObjects];
    if ([insertedObjects count] > 0) {
        BOOL insertSuccess = [self SM_handleInsertedObjects:insertedObjects inContext:context options:options error:error networkAvailable:networkAvailable];
        if (!insertSuccess) {
            return nil;
        }
    }
    NSSet *updatedObjects = [saveRequest updatedObjects];
    if ([updatedObjects count] > 0) {
        BOOL updateSuccess = [self SM_handleUpdatedObjects:updatedObjects inContext:context options:options error:error networkAvailable:networkAvailable];
        if (!updateSuccess) {
            return nil;
        }
    }
    NSSet *deletedObjects = [saveRequest deletedObjects];
    if ([deletedObjects count] > 0) {
        BOOL deleteSuccess = [self SM_handleDeletedObjects:deletedObjects inContext:context options:options error:error networkAvailable:networkAvailable];
        if (!deleteSuccess) {
            return nil;
        }
    }
    
    return [NSArray array];
}

- (BOOL)SM_checkNetworkAvailability
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    __block BOOL networkAvailable = NO;
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Network Availability Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    SMQuery *query = [[SMQuery alloc] initWithSchema:[[self.coreDataStore session] userSchema]];
    SMRequestOptions *requestOptions = [SMRequestOptions options];
    
    requestOptions.tryRefreshToken = NO;
    
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    SMRequestOptions *options = [threadDictionary objectForKey:SMRequestSpecificOptions];
    if (!options) {
        requestOptions.isSecure = [self.coreDataStore.globalRequestOptions isSecure];
    } else {
        requestOptions.isSecure = [options isSecure];
    }
    
    dispatch_group_enter(group);
    [[self coreDataStore] performCount:query options:requestOptions successCallbackQueue:queue failureCallbackQueue:queue onSuccess:^(NSNumber *count) {
        networkAvailable = YES;
        dispatch_group_leave(group);
    } onFailure:^(NSError *error) {
        if ([error code] == SMErrorNetworkNotReachable) {
            networkAvailable = NO;
        } else {
            networkAvailable = YES;
        }
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    
    return networkAvailable;
    
}

- (BOOL)SM_handleInsertedObjects:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    if (networkAvailable) {
        return [self SM_handleInsertedObjectsWhenOnline:insertedObjects inContext:context options:options error:error];
    } else {
        return [self SM_handleInsertedObjectsWhenOffline:insertedObjects inContext:context options:options error:error];
    }
}

- (BOOL)SM_handleInsertedObjectsWhenOnline:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (SM_CORE_DATA_DEBUG) { DLog(@"objects to be inserted are %@", truncateOutputIfExceedsMaxLogLength(insertedObjects))}
    
    __block BOOL success = YES;
    //__block SMRequestOptions *optionsForInsert = [options copy];
    
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Inserted Object Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    __block NSMutableArray *secureOperations = [NSMutableArray array];
    __block NSMutableArray *regularOperations = [NSMutableArray array];
    __block NSMutableArray *failedRequests = [NSMutableArray array];
    __block NSMutableArray *failedRequestsWithUnauthorizedResponse = [NSMutableArray array];
    __block BOOL previousStateOfHTTPSOption = [options isSecure];
    __block NSMutableArray *objectsToBeCached = [NSMutableArray array];
    
    [insertedObjects enumerateObjectsUsingBlock:^(id managedObject, BOOL *stop) {
        
        // Create operation for inserted object
        
        NSDictionary *serializedObjDict = [managedObject SMDictionarySerialization];
        NSString *schemaName = [managedObject SMSchema];
        __block NSString *insertedObjectID = [managedObject SMObjectId];
        
        // If superclass is SMUserNSManagedObject, add password
        if ([managedObject isKindOfClass:[SMUserManagedObject class]]) {
            BOOL addPasswordSuccess = [self SM_addPasswordToSerializedDictionary:&serializedObjDict originalObject:managedObject];
            if (!addPasswordSuccess)
            {
                *error = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorPasswordForUserObjectNotFound userInfo:nil];
                *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
                *stop = YES;
            }
            [options setIsSecure:YES];
        }
        
        if (!*stop) {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Serialized object dictionary: %@", truncateOutputIfExceedsMaxLogLength(serializedObjDict)) }
            // add relationship headers if needed
            NSMutableDictionary *headerDict = [NSMutableDictionary dictionary];
            if ([serializedObjDict objectForKey:StackMobRelationsKey]) {
                [headerDict setObject:[serializedObjDict objectForKey:StackMobRelationsKey] forKey:StackMobRelationsKey];
                [options setHeaders:headerDict];
            }
            
            SMResultSuccessBlock operationSuccesBlock = ^(NSDictionary *theObject){
                if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore inserted object %@ on schema %@", truncateOutputIfExceedsMaxLogLength(theObject) , schemaName) }
                if ([managedObject isKindOfClass:[SMUserManagedObject class]]) {
                    [managedObject removePassword];
                }
                
                // Add object to list of objects to be cached [primaryKey, dictionary of object, entity desc, context]
                NSArray *objectReadyForCache = [NSArray arrayWithObjects:[managedObject valueForKey:[managedObject primaryKeyField]], theObject, [managedObject entity], context, nil];
                [objectsToBeCached addObject:objectReadyForCache];
                
            };
            
            SMCoreDataSaveFailureBlock operationFailureBlock = ^(NSURLRequest *theRequest, NSError *theError, NSDictionary *theObject, SMRequestOptions *theOptions, SMResultSuccessBlock originalSuccessBlock){
                
                if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore failed to insert object %@ on schema %@", truncateOutputIfExceedsMaxLogLength(theObject), schemaName) }
                if (SM_CORE_DATA_DEBUG) { DLog(@"the error userInfo is %@", [theError userInfo]) }
                
                NSDictionary *failedRequestDict = [NSDictionary dictionaryWithObjectsAndKeys:theRequest, SMFailedRequest, theError, SMFailedRequestError, insertedObjectID, SMFailedRequestObjectPrimaryKey, [managedObject entity], SMFailedRequestObjectEntity, theOptions, SMFailedRequestOptions, originalSuccessBlock, SMFailedRequestOriginalSuccessBlock, nil];
                
                // Add failed request to correct array
                if ([theError code] == SMErrorUnauthorized) {
                    [failedRequestsWithUnauthorizedResponse addObject:failedRequestDict];
                } else {
                    [failedRequests addObject:failedRequestDict];
                }
                
            };
            
            AFJSONRequestOperation *op = [[self coreDataStore] postOperationForObject:[serializedObjDict objectForKey:SerializedDictKey] inSchema:schemaName options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:operationSuccesBlock onFailure:operationFailureBlock];
            
            options.isSecure ? [secureOperations addObject:op] : [regularOperations addObject:op];
            
        } else {
            success = NO;
        }
        
    }];
    
    success = [self SM_enqueueRegularOperations:regularOperations secureOperations:secureOperations withGroup:group queue:queue options:options refreshAndRetryUnauthorizedRequests:failedRequestsWithUnauthorizedResponse failedRequests:failedRequests error:error];
    
    [self SM_cacheObjects:objectsToBeCached];
    
    [options setIsSecure:previousStateOfHTTPSOption];

#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    return success;
    
}

- (BOOL)SM_handleInsertedObjectsWhenOffline:(NSSet *)insertedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    __block NSMutableArray *objectsToBeCached = [NSMutableArray arrayWithCapacity:[insertedObjects count]];
    __block NSMutableArray *dirtyObjects = [NSMutableArray array];
    
    [insertedObjects enumerateObjectsUsingBlock:^(id managedObject, BOOL *stop) {
        
        // Possibly just need to serialize dictionary once?
        
        // Add dictionary rep of attributes
        NSMutableDictionary *dictionaryRepOfManagedObject = [NSMutableDictionary dictionary];
        [dictionaryRepOfManagedObject addEntriesFromDictionary:[managedObject dictionaryWithValuesForKeys:[[[managedObject entity] attributesByName] allKeys]]];
        
        // Add dictionary rep of relationships
        [dictionaryRepOfManagedObject addEntriesFromDictionary:[self SM_extractRelationshipships:[managedObject dictionaryWithValuesForKeys:[[[managedObject entity] relationshipsByName] allKeys]]]];
        
        // Assign lastmoddate and createddate?
        
        // Add object to list of objects to be cached [primaryKey, dictionary of object, entity desc, context]
        NSArray *objectReadyForCache = [NSArray arrayWithObjects:[managedObject valueForKey:[managedObject primaryKeyField]], dictionaryRepOfManagedObject, [managedObject entity], context, nil];
        [objectsToBeCached addObject:objectReadyForCache];
        
        // Add object to dirty queue
        [dirtyObjects addObject:[managedObject valueForKey:[managedObject primaryKeyField]]];
        
    }];
    
    // Cache objects
    [self SM_cacheObjects:objectsToBeCached];
    
    // Save dirty objects
    [self SM_addPrimaryKeysToDirtyQueueAndSave:dirtyObjects state:0];
    
    return YES;
    
    /*
     if (error != NULL) {
     NSError *notReachableError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorNetworkNotReachable userInfo:nil];
     *error = (__bridge id)(__bridge_retained CFTypeRef)notReachableError;
     }
     return NO;
     */
}

- (NSDictionary *)SM_extractRelationshipships:(NSDictionary *)relationshipsDictionary
{
    __block NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionary];
    
    [relationshipsDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSMutableSet class]]) {
            __block NSMutableArray *arrayToSet = [NSMutableArray array];
            [value enumerateObjectsUsingBlock:^(id managedObject, NSUInteger idx, BOOL *end) {
                [arrayToSet addObject:[self referenceObjectForObjectID:[managedObject objectID]]];
            }];
            [returnDictionary setObject:[NSArray arrayWithArray:arrayToSet] forKey:key];
        } else if ([value isKindOfClass:[NSManagedObjectID class]]) {
            [returnDictionary setObject:[self referenceObjectForObjectID:value] forKey:key];
        } else {
            [returnDictionary setObject:value forKey:key];
        }
    }];
    
    return returnDictionary;
}

- (BOOL)SM_handleUpdatedObjects:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (networkAvailable) {
        return [self SM_handleUpdatedObjectsWhenOnline:updatedObjects inContext:context options:options error:error];
    } else {
        return [self SM_handleUpdatedObjectsWhenOffline:updatedObjects inContext:context options:options error:error];
    }
}

- (BOOL)SM_handleUpdatedObjectsWhenOnline:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (SM_CORE_DATA_DEBUG) { DLog(@"objects to be updated are %@", truncateOutputIfExceedsMaxLogLength(updatedObjects)) }
    __block BOOL success = YES;
    
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Updated Objects Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    __block NSMutableArray *secureOperations = [NSMutableArray array];
    __block NSMutableArray *regularOperations = [NSMutableArray array];
    __block NSMutableArray *failedRequests = [NSMutableArray array];
    __block NSMutableArray *failedRequestsWithUnauthorizedResponse = [NSMutableArray array];
    __block NSMutableArray *objectsToBeCached = [NSMutableArray array];
    
    [updatedObjects enumerateObjectsUsingBlock:^(id managedObject, BOOL *stop) {
        
        // Create operation for updated object
        
        NSDictionary *serializedObjDict = [managedObject SMDictionarySerialization];
        NSString *schemaName = [managedObject SMSchema];
        __block NSString *updatedObjectID = [managedObject SMObjectId];
        
        if (SM_CORE_DATA_DEBUG) { DLog(@"Serialized object dictionary: %@", truncateOutputIfExceedsMaxLogLength(serializedObjDict)) }
        
        // Create success/failure blocks
        SMResultSuccessBlock operationSuccesBlock = ^(NSDictionary *theObject){
            if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore updated object %@ on schema %@", truncateOutputIfExceedsMaxLogLength(theObject) , schemaName) }
            
            // Add object to list of objects to be cached [primaryKey, dictionary of object, entity desc, context]
            NSArray *objectReadyForCache = [NSArray arrayWithObjects:[managedObject valueForKey:[managedObject primaryKeyField]], theObject, [managedObject entity], context, nil];
            [objectsToBeCached addObject:objectReadyForCache];
            
        };
        
        SMCoreDataSaveFailureBlock operationFailureBlock = ^(NSURLRequest *theRequest, NSError *theError, NSDictionary *theObject, SMRequestOptions *theOptions, SMResultSuccessBlock originalSuccessBlock){
            
            if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore failed to update object %@ on schema %@", truncateOutputIfExceedsMaxLogLength(theObject), schemaName) }
            if (SM_CORE_DATA_DEBUG) { DLog(@"the error userInfo is %@", [theError userInfo]) }
            
            NSDictionary *failedRequestDict = [NSDictionary dictionaryWithObjectsAndKeys:theRequest, SMFailedRequest, theError, SMFailedRequestError, updatedObjectID, SMFailedRequestObjectPrimaryKey, [managedObject entity], SMFailedRequestObjectEntity, theOptions, SMFailedRequestOptions, originalSuccessBlock, SMFailedRequestOriginalSuccessBlock, nil];
            
            // Add failed request to correct array
            if ([theError code] == SMErrorUnauthorized) {
                [failedRequestsWithUnauthorizedResponse addObject:failedRequestDict];
            } else {
                [failedRequests addObject:failedRequestDict];
            }
            
        };
        
        // if there are relationships present in the update, send as a POST
        AFJSONRequestOperation *op = nil;
        if ([serializedObjDict objectForKey:StackMobRelationsKey]) {
            
            // add relationship headers if needed
            NSMutableDictionary *headerDict = [NSMutableDictionary dictionary];
            if ([serializedObjDict objectForKey:StackMobRelationsKey]) {
                [headerDict setObject:[serializedObjDict objectForKey:StackMobRelationsKey] forKey:StackMobRelationsKey];
                [options setHeaders:headerDict];
            }
            
            op = [[self coreDataStore] postOperationForObject:[serializedObjDict objectForKey:SerializedDictKey] inSchema:schemaName options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:operationSuccesBlock onFailure:operationFailureBlock];
            
            
        } else {
            
            op = [[self coreDataStore] putOperationForObjectID:updatedObjectID inSchema:schemaName update:[serializedObjDict objectForKey:SerializedDictKey] options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:operationSuccesBlock onFailure:operationFailureBlock];
            
        }
        
        options.isSecure ? [secureOperations addObject:op] : [regularOperations addObject:op];
        
    }];
    
    success = [self SM_enqueueRegularOperations:regularOperations secureOperations:secureOperations withGroup:group queue:queue options:options refreshAndRetryUnauthorizedRequests:failedRequestsWithUnauthorizedResponse failedRequests:failedRequests error:error];
    
    [self SM_cacheObjects:objectsToBeCached];
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    return success;
    
}

- (BOOL)SM_handleUpdatedObjectsWhenOffline:(NSSet *)updatedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    __block NSMutableArray *objectsToBeCached = [NSMutableArray arrayWithCapacity:[updatedObjects count]];
    __block NSMutableArray *dirtyObjects = [NSMutableArray array];
    
    [updatedObjects enumerateObjectsUsingBlock:^(id managedObject, BOOL *stop) {
        
        // Possibly just need to serialize dictionary once?
        
        // Add dictionary rep of attributes
        NSMutableDictionary *dictionaryRepOfManagedObject = [NSMutableDictionary dictionary];
        [dictionaryRepOfManagedObject addEntriesFromDictionary:[managedObject dictionaryWithValuesForKeys:[[[managedObject entity] attributesByName] allKeys]]];
        
        // Add dictionary rep of relationships
        [dictionaryRepOfManagedObject addEntriesFromDictionary:[self SM_extractRelationshipships:[managedObject dictionaryWithValuesForKeys:[[[managedObject entity] relationshipsByName] allKeys]]]];
        
        // Assign lastmoddate and createddate?
        
        
        // Add object to list of objects to be cached [primaryKey, dictionary of object, entity desc, context]
        NSArray *objectReadyForCache = [NSArray arrayWithObjects:[managedObject valueForKey:[managedObject primaryKeyField]], dictionaryRepOfManagedObject, [managedObject entity], context, nil];
        [objectsToBeCached addObject:objectReadyForCache];
        
        // Add object to dirty queue
        [dirtyObjects addObject:[managedObject valueForKey:[managedObject primaryKeyField]]];
        
    }];
    
    // Cache objects
    [self SM_cacheObjects:objectsToBeCached];
    
    // Save dirty objects
    [self SM_addPrimaryKeysToDirtyQueueAndSave:dirtyObjects state:1];
    
    return YES;
    
    /*
     if (error != NULL) {
     NSError *notReachableError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorNetworkNotReachable userInfo:nil];
     *error = (__bridge id)(__bridge_retained CFTypeRef)notReachableError;
     }
     return NO;
     */
}

- (BOOL)SM_handleDeletedObjects:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error networkAvailable:(BOOL)networkAvailable
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (networkAvailable) {
        return [self SM_handleDeletedObjectsWhenOnline:deletedObjects inContext:context options:options error:error];
    } else {
        return [self SM_handleDeletedObjectsWhenOffline:deletedObjects inContext:context options:options error:error];
    }
}

- (BOOL)SM_handleDeletedObjectsWhenOnline:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context  options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (SM_CORE_DATA_DEBUG) { DLog(@"objects to be deleted are %@", truncateOutputIfExceedsMaxLogLength(deletedObjects)) }
    
    __block BOOL success = YES;
    
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Deleted Objects Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    __block NSMutableArray *secureOperations = [NSMutableArray array];
    __block NSMutableArray *regularOperations = [NSMutableArray array];
    __block NSMutableArray *failedRequests = [NSMutableArray array];
    __block NSMutableArray *failedRequestsWithUnauthorizedResponse = [NSMutableArray array];
    __block NSMutableArray *deletedObjectIDs = [NSMutableArray array];
    
    [deletedObjects enumerateObjectsUsingBlock:^(id managedObject, BOOL *stop) {
        
        // Create operation for updated object
        NSString *schemaName = [managedObject SMSchema];
        __block NSString *deletedObjectID = [managedObject SMObjectId];
        __block NSString *deletedObjectEntityname = [[managedObject entity] name];
        
        // Create success/failure blocks
        SMResultSuccessBlock operationSuccesBlock = ^(NSDictionary *theObject){
            if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore deleted object %@ on schema %@", deletedObjectID , schemaName) }
            
            // Purge cache of object
            [deletedObjectIDs addObject:[NSDictionary dictionaryWithObjectsAndKeys:deletedObjectID, ObjectID, deletedObjectEntityname, ObjectEntityName, nil]];
            
        };
        
        SMCoreDataSaveFailureBlock operationFailureBlock = ^(NSURLRequest *theRequest, NSError *theError, NSDictionary *theObject, SMRequestOptions *theOptions, SMResultSuccessBlock originalSuccessBlock){
            
            if (SM_CORE_DATA_DEBUG) { DLog(@"SMIncrementalStore failed to update object %@ on schema %@", truncateOutputIfExceedsMaxLogLength(theObject), schemaName) }
            if (SM_CORE_DATA_DEBUG) { DLog(@"the error userInfo is %@", [theError userInfo]) }
            
            NSDictionary *failedRequestDict = [NSDictionary dictionaryWithObjectsAndKeys:theRequest, SMFailedRequest, theError, SMFailedRequestError, deletedObjectID, SMFailedRequestObjectPrimaryKey, [managedObject entity], SMFailedRequestObjectEntity, theOptions, SMFailedRequestOptions, originalSuccessBlock, SMFailedRequestOriginalSuccessBlock, nil];
            
            // Add failed request to correct array
            if ([theError code] == SMErrorUnauthorized) {
                [failedRequestsWithUnauthorizedResponse addObject:failedRequestDict];
            } else {
                [failedRequests addObject:failedRequestDict];
            }
            
        };
        
        // if there are relationships present in the update, send as a POST
        AFJSONRequestOperation *op = [[self coreDataStore] deleteOperationForObjectID:deletedObjectID inSchema:schemaName options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:operationSuccesBlock onFailure:operationFailureBlock];
        
        options.isSecure ? [secureOperations addObject:op] : [regularOperations addObject:op];
        
    }];
    
    success = [self SM_enqueueRegularOperations:regularOperations secureOperations:secureOperations withGroup:group queue:queue options:options refreshAndRetryUnauthorizedRequests:failedRequestsWithUnauthorizedResponse failedRequests:failedRequests error:error];
    
    if (SM_CACHE_ENABLED && success && [deletedObjectIDs count] > 0) {
        [self SM_purgeObjectsFromCacheByStackMobIDInfo:deletedObjectIDs];
    }
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    return success;
    
}

- (BOOL)SM_handleDeletedObjectsWhenOffline:(NSSet *)deletedObjects inContext:(NSManagedObjectContext *)context  options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    
    __block NSMutableArray *deletedObjectIDs = [NSMutableArray array];
    __block NSMutableArray *deletedObjectInfo = [NSMutableArray array];
    [deletedObjects enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
        NSString *primaryKey = [obj valueForKey:[obj primaryKeyField]];
        [deletedObjectInfo addObject:[NSDictionary dictionaryWithObjectsAndKeys:primaryKey, ObjectID, [[obj entity] name], ObjectEntityName, nil]];
        [deletedObjectIDs addObject:primaryKey];
    }];
    
    BOOL purgeSuccess = [self SM_purgeObjectsFromCacheByStackMobIDInfo:deletedObjectInfo];
    if (!purgeSuccess) {
        
    }
    
    [self SM_addPrimaryKeysToDirtyQueueAndSave:deletedObjectIDs state:2];
    
    return YES;
    
    /*
    if (SM_CORE_DATA_DEBUG) { DLog() }
    if (error != NULL) {
        NSError *notReachableError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorNetworkNotReachable userInfo:nil];
        *error = (__bridge id)(__bridge_retained CFTypeRef)notReachableError;
    }
    return NO;
    */
}


- (BOOL)SM_enqueueRegularOperations:(NSMutableArray *)regularOperations secureOperations:(NSMutableArray *)secureOperations withGroup:(dispatch_group_t)group queue:(dispatch_queue_t)queue options:(SMRequestOptions *)options refreshAndRetryUnauthorizedRequests:(NSMutableArray *)failedRequestsWithUnauthorizedResponse failedRequests:(NSMutableArray *)failedRequests error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    // Refresh access token if needed before initial enqueue of operations
    __block BOOL success = [self SM_doTokenRefreshIfNeededWithGroup:group queue:queue options:options error:error];
    
    if (success) {
        [self SM_enqueueOperations:secureOperations  dispatchGroup:group completionBlockQueue:queue secure:YES];
        [self SM_enqueueOperations:regularOperations dispatchGroup:group completionBlockQueue:queue secure:NO];
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        // If there were 401s, refresh token is valid, refresh token is present and token has expired, attempt refresh and reprocess
        if ([failedRequestsWithUnauthorizedResponse count] > 0) {
            
            if ([self.coreDataStore.session eligibleForTokenRefresh:options]) {
                
                // If we are refreshing, wait for refresh with 5 sec timeout
                __block BOOL refreshSuccess = NO;
                
                if (self.coreDataStore.session.refreshing) {
                    
                    [self SM_waitForRefreshingWithTimeout:5];
                    
                } else {
                    
                    [options setTryRefreshToken:NO];
                    dispatch_group_enter(group);
                    self.coreDataStore.session.refreshing = YES;//Don't ever trigger two refreshToken calls
                    [self.coreDataStore.session doTokenRequestWithEndpoint:@"refreshToken" credentials:[NSDictionary dictionaryWithObjectsAndKeys:self.coreDataStore.session.refreshToken, @"refresh_token", nil] options:[SMRequestOptions options] successCallbackQueue:queue failureCallbackQueue:queue onSuccess:^(NSDictionary *userObject) {
                        refreshSuccess = YES;
                        dispatch_group_leave(group);
                    } onFailure:^(NSError *theError) {
                        
                        refreshSuccess = NO;
                        success = NO;
                        [failedRequests addObjectsFromArray:failedRequestsWithUnauthorizedResponse];
                        [self SM_setErrorAndUserInfoWithFailedOperations:failedRequests errorCode:SMErrorRefreshTokenFailed error:error];
                        
                        dispatch_group_leave(group);
                    }];
                    
                    
                    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
                }
                
                if (self.coreDataStore.session.refreshing) {
                    
                    refreshSuccess = NO;
                    success = NO;
                    [failedRequests addObjectsFromArray:failedRequestsWithUnauthorizedResponse];
                    [self SM_setErrorAndUserInfoWithFailedOperations:failedRequests errorCode:SMErrorRefreshTokenInProgress error:error];
                    
                } else {
                    refreshSuccess = YES;
                }
                
                if (refreshSuccess) {
                    
                    // Retry Failed Requests
                    
                    [secureOperations removeAllObjects];
                    [regularOperations removeAllObjects];
                    
                    [failedRequestsWithUnauthorizedResponse enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                        SMRequestOptions *retryOptions = [obj objectForKey:SMFailedRequestOptions];
                        
                        SMFullResponseSuccessBlock retrySuccessBlock = [self.coreDataStore SMFullResponseSuccessBlockForResultSuccessBlock:[obj objectForKey:SMFailedRequestOriginalSuccessBlock]];
                        
                        SMFullResponseFailureBlock retryFailureBlock = ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *retryError, id JSON) {
                            
                            NSDictionary *failedRequestDict = [NSDictionary dictionaryWithObjectsAndKeys:[self.coreDataStore errorFromResponse:response JSON:JSON], SMFailedRequestError, [obj objectForKey:SMFailedRequestObjectPrimaryKey], SMFailedRequestObjectPrimaryKey, [obj objectForKey:SMFailedRequestObjectEntity], SMFailedRequestObjectEntity, nil];
                            [failedRequests addObject:failedRequestDict];
                            
                        };
                        
                        AFJSONRequestOperation *op = [self.coreDataStore newOperationForRequest:[obj objectForKey:SMFailedRequest] options:[obj objectForKey:SMFailedRequestOptions] successCallbackQueue:queue failureCallbackQueue:queue onSuccess:retrySuccessBlock onFailure:retryFailureBlock];
                        
                        retryOptions.isSecure ? [secureOperations addObject:op] : [regularOperations addObject:op];
                    }];
                    
                    [self SM_enqueueOperations:secureOperations  dispatchGroup:group completionBlockQueue:queue secure:YES];
                    [self SM_enqueueOperations:regularOperations dispatchGroup:group completionBlockQueue:queue secure:NO];
                    
                    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
                    
                }
                
            } else {
                [failedRequests addObjectsFromArray:failedRequestsWithUnauthorizedResponse];
            }
        }
        
        // Error if any failed requests have made it to this point
        if ([failedRequests count] > 0) {
            success = NO;
            [self SM_setErrorAndUserInfoWithFailedOperations:failedRequests errorCode:SMErrorCoreDataSave error:error];
        }
    }
    
    return success;
    
}


- (BOOL)SM_setErrorAndUserInfoWithFailedOperations:(NSMutableArray *)failedOperations errorCode:(int)errorCode error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    if (error != NULL && *error == nil) {
        __block NSMutableArray *failedInsertedObjects = [NSMutableArray array];
        [failedOperations enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSManagedObjectID *oid = [self newObjectIDForEntity:[obj objectForKey:SMFailedRequestObjectEntity] referenceObject:[obj objectForKey:SMFailedRequestObjectPrimaryKey]];
            NSDictionary *failedObject = [NSDictionary dictionaryWithObjectsAndKeys:oid, SMFailedManagedObjectID, [obj objectForKey:SMFailedRequestError], SMFailedManagedObjectError, nil];
            [failedInsertedObjects addObject:failedObject];
        }];
        NSError *errorToSet = nil;
        if (errorCode == SMErrorRefreshTokenFailed && self.coreDataStore.session.tokenRefreshFailureBlock) {
            errorToSet = [[NSError alloc] initWithDomain:SMErrorDomain code:errorCode userInfo:[NSDictionary dictionaryWithObjectsAndKeys:failedInsertedObjects, SMInsertedObjectFailures, self.coreDataStore.session.tokenRefreshFailureBlock, SMFailedRefreshBlock, nil]];
        } else {
            errorToSet = [[NSError alloc] initWithDomain:SMErrorDomain code:errorCode userInfo:[NSDictionary dictionaryWithObjectsAndKeys:failedInsertedObjects, SMInsertedObjectFailures, nil]];
        }
        *error = (__bridge id)(__bridge_retained CFTypeRef)errorToSet;
    }
    [failedOperations removeAllObjects];
    return YES;
}

- (void)SM_waitForRefreshingWithTimeout:(int)timeout
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    if (timeout == 0 || !self.coreDataStore.session.refreshing) {
        return;
    }
    
    sleep(1);
    
    [self SM_waitForRefreshingWithTimeout:(timeout - 1)];
    
}

- (void)SM_enqueueOperations:(NSArray *)ops dispatchGroup:(dispatch_group_t)group completionBlockQueue:(dispatch_queue_t)queue secure:(BOOL)isSecure
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    if ([ops count] > 0) {
        dispatch_group_enter(group);
        [[[self.coreDataStore session] oauthClientWithHTTPS:isSecure] enqueueBatchOfHTTPRequestOperations:ops completionBlockQueue:queue progressBlock:^(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations) {
            
        } completionBlock:^(NSArray *operations) {
            dispatch_group_leave(group);
        }];
    }
}

- (BOOL)SM_doTokenRefreshIfNeededWithGroup:(dispatch_group_t)group queue:(dispatch_queue_t)queue options:(SMRequestOptions *)options error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block BOOL success = YES;
    if ([self.coreDataStore.session eligibleForTokenRefresh:options]) {
        
        if (self.coreDataStore.session.refreshing) {
            
            [self SM_waitForRefreshingWithTimeout:5];
            
        } else {
            
            [options setTryRefreshToken:NO];
            dispatch_group_enter(group);
            self.coreDataStore.session.refreshing = YES;//Don't ever trigger two refreshToken calls
            [self.coreDataStore.session doTokenRequestWithEndpoint:@"refreshToken" credentials:[NSDictionary dictionaryWithObjectsAndKeys:self.coreDataStore.session.refreshToken, @"refresh_token", nil] options:[SMRequestOptions options] successCallbackQueue:queue failureCallbackQueue:queue onSuccess:^(NSDictionary *userObject) {
                dispatch_group_leave(group);
            } onFailure:^(NSError *theError) {
                
                success = NO;
                if (error != NULL) {
                    // Check if tokenRefreshFailBlock
                    NSError *refreshError = nil;
                    if (self.coreDataStore.session.tokenRefreshFailureBlock) {
                        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:self.coreDataStore.session.tokenRefreshFailureBlock, SMFailedRefreshBlock, nil];
                        refreshError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorRefreshTokenFailed userInfo:userInfo];
                    } else {
                        refreshError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorRefreshTokenFailed userInfo:nil];
                    }
                    
                    *error = (__bridge id)(__bridge_retained CFTypeRef)refreshError;
                }
                dispatch_group_leave(group);
            }];
            
            
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        }
        
        if (self.coreDataStore.session.refreshing) {
            
            success = NO;
            if (error != NULL) {
                NSError *refreshError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorRefreshTokenInProgress userInfo:nil];
                *error = (__bridge id)(__bridge_retained CFTypeRef)refreshError;
            }
            
        }
        
    }
    
    return success;
}

////////////////////////////
#pragma mark - Fetch Requests
////////////////////////////

/*
 If it is NSCountResultType, the method should return an array containing an NSNumber whose value is the count of of all objects in the store matching the request.
 
 You must support the following properties of NSFetchRequest: entity, predicate, sortDescriptors, fetchLimit, resultType, includesSubentities, returnsDistinctResults (in the case of NSDictionaryResultType), propertiesToFetch (in the case of NSDictionaryResultType), fetchOffset, fetchBatchSize, shouldRefreshFetchedObjects, propertiesToGroupBy, and havingPredicate. If a store does not have underlying support for a feature (propertiesToGroupBy, havingPredicate), it should either emulate the feature in memory or return an error. Note that these are the properties that directly affect the contents of the array to be returned.
 
 You may optionally ignore the following properties of NSFetchRequest: includesPropertyValues, returnsObjectsAsFaults, relationshipKeyPathsForPrefetching, and includesPendingChanges (this is handled by the managed object context). (These are properties that allow for optimization of I/O and do not affect the results array contents directly.)
 */
- (id)SM_handleFetchRequest:(NSPersistentStoreRequest *)request
                withContext:(NSManagedObjectContext *)context
                      error:(NSError * __autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    SMRequestOptions *options = [threadDictionary objectForKey:SMRequestSpecificOptions];
    if (!options) {
        options = self.coreDataStore.globalRequestOptions;
    }
    
    NSFetchRequest *fetchRequest = (NSFetchRequest *)request;
    switch (fetchRequest.resultType) {
        case NSManagedObjectResultType:
            return [self SM_fetchObjects:fetchRequest withContext:context options:options error:error];
            break;
        case NSManagedObjectIDResultType:
            return [self SM_fetchObjectIDs:fetchRequest withContext:context options:options error:error];
            break;
        case NSDictionaryResultType:
            [NSException raise:SMExceptionIncompatibleObject format:@"Unimplemented result type requested."];
            break;
        case NSCountResultType:
            [NSException raise:SMExceptionIncompatibleObject format:@"Unimplemented result type requested."];
            break;
        default:
            [NSException raise:SMExceptionIncompatibleObject format:@"Unknown result type requested."];
            break;
    }
    return nil;
}

- (id)SM_fetchObjectsFromNetwork:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError * __autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    // Build query for StackMob
    SMQuery *query = [self queryForFetchRequest:fetchRequest error:error];
    
    if (query == nil) {
        if (error) {
            *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
        }
        return nil;
    }
    
    __block NSArray *resultsWithoutOID;
    
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Fetch Objects Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    dispatch_group_enter(group);
    [self.coreDataStore performQuery:query options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:^(NSArray *results) {
        resultsWithoutOID = results;
        dispatch_group_leave(group);
    } onFailure:^(NSError *queryError) {
        
        if (error != NULL) {
            *error = (__bridge id)(__bridge_retained CFTypeRef)queryError;
        }
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    
    if (*error != nil) {
        return nil;
    }
    
    if (SM_CACHE_ENABLED && ![self containsSMPredicate:[fetchRequest predicate]]) {
        
        // Network fetch was successful, run same fetch on local cache and delete results
        NSError *fetchOnCacheError = nil;
        NSArray *cacheResults = [self.localManagedObjectContext executeFetchRequest:fetchRequest error:&fetchOnCacheError];
        
        if (fetchOnCacheError) {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Error fetching from cache, %@", fetchOnCacheError) }
        }
        
        if ([cacheResults count] > 0) {
            NSMutableArray *cacheObjectsToBeDeleted = [NSMutableArray array];
            [cacheResults enumerateObjectsUsingBlock:^(id cacheObject, NSUInteger idx, BOOL *stop) {
                [cacheObjectsToBeDeleted addObject:cacheObject];
            }];
            
            BOOL purgeSuccess = [self SM_purgeCacheManagedObjectsFromCache:cacheObjectsToBeDeleted];
            if (!purgeSuccess) {
                if (SM_CORE_DATA_DEBUG) { DLog(@"Purge Unsuccessful") }
            }
        }
        
        // Obtain the primary key for the entity
        __block NSString *primaryKeyField = nil;
        
        @try {
            primaryKeyField = [fetchRequest.entity SMFieldNameForProperty:[[fetchRequest.entity propertiesByName] objectForKey:[fetchRequest.entity primaryKeyField]]];
        }
        @catch (NSException *exception) {
            primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
        }
        
        // For each result of the fetch
        NSArray *results = [resultsWithoutOID map:^(id item) {
            
            id remoteID = [item objectForKey:primaryKeyField];
            
            if (!remoteID) {
                [NSException raise:SMExceptionIncompatibleObject format:@"No key for supposed primary key field %@ for item %@", primaryKeyField, item];
            }
            
            NSManagedObjectID *sm_managedObjectID = [self newObjectIDForEntity:fetchRequest.entity referenceObject:remoteID];
            NSManagedObject *sm_managedObject = [context objectWithID:sm_managedObjectID];
            NSDictionary *serializedObjectDict = [self SM_responseSerializationForDictionary:item schemaEntityDescription:fetchRequest.entity managedObjectContext:context includeRelationships:YES];
            
            // If the object is not marked faulted, it exists in memory and its values should be replaced with up-to-date fetched values.
            if (![sm_managedObject isFault]) {
                [self SM_populateManagedObject:sm_managedObject withDictionary:serializedObjectDict entity:[sm_managedObject entity]];
            }
            
            // Obtain cache object representation, or create if needed
            
            NSManagedObject *cacheManagedObject = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:remoteID entityName:[[sm_managedObject entity] name] createIfNeeded:YES]];
            
            [self SM_populateCacheManagedObject:cacheManagedObject withDictionary:serializedObjectDict entity:fetchRequest.entity];
            return sm_managedObject;
            
        }];
        
        NSError *cacheSaveError = nil;
        [self SM_saveCache:&cacheSaveError];
        if (cacheSaveError) {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Cache save unsuccessful, %@", cacheSaveError) }
        }
        
        return results;
        
    } else {
        
        // Obtain the primary key for the entity
        __block NSString *primaryKeyField = nil;
        
        @try {
            primaryKeyField = [fetchRequest.entity SMFieldNameForProperty:[[fetchRequest.entity propertiesByName] objectForKey:[fetchRequest.entity primaryKeyField]]];
        }
        @catch (NSException *exception) {
            primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
        }
        
        // For each result of the fetch
        NSArray *results = [resultsWithoutOID map:^(id item) {
            
            id remoteID = [item objectForKey:primaryKeyField];
            
            if (!remoteID) {
                [NSException raise:SMExceptionIncompatibleObject format:@"No key for supposed primary key field %@ for item %@", primaryKeyField, item];
            }
            
            NSManagedObjectID *sm_managedObjectID = [self newObjectIDForEntity:fetchRequest.entity referenceObject:remoteID];
            NSManagedObject *sm_managedObject = [context objectWithID:sm_managedObjectID];
            NSDictionary *serializedObjectDict = [self SM_responseSerializationForDictionary:item schemaEntityDescription:fetchRequest.entity managedObjectContext:context includeRelationships:YES];
            
            // If the object is not marked faulted, it exists in memory and its values should be replaced with up-to-date fetched values.
            if (![sm_managedObject isFault]) {
                [self SM_populateManagedObject:sm_managedObject withDictionary:serializedObjectDict entity:[sm_managedObject entity]];
            }
            
            return sm_managedObject;
            
        }];
        
        return results;

    }
    
}

- (BOOL) containsSMPredicate:(NSPredicate *)predicate {
    
    if ([predicate isKindOfClass:[SMPredicate class]]) {
        return YES;
    }
    else if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate *compoundPredicate = (NSCompoundPredicate *)predicate;
        for (NSPredicate *subPredicate in [compoundPredicate subpredicates]) {
             if([self containsSMPredicate:subPredicate])
                 return YES;
        }
        
    }
    
    return NO;
}

- (id)SM_fetchObjectsFromCache:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    if ([self containsSMPredicate:[fetchRequest predicate]]) {
        return [NSArray array];
    }
    
    
    __block NSArray *localCacheResults = nil;
    __block NSError *localCacheError = nil;
    [self.localManagedObjectContext performBlockAndWait:^{
        localCacheResults = [self.localManagedObjectContext executeFetchRequest:fetchRequest error:&localCacheError];
    }];
    
    // Error check
    if (localCacheError != nil) {
        if (error != NULL) {
            *error = (__bridge id)(__bridge_retained CFTypeRef)localCacheError;
        }
        return nil;
    }
    
    __block NSString *primaryKeyField = nil;
    @try {
        primaryKeyField = [fetchRequest.entity primaryKeyField];
    }
    @catch (NSException *exception) {
        primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
    }
    
    __block NSMutableArray *results = [NSMutableArray array];
    
    [localCacheResults enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        // Only include non-nil references
        NSString *relatedObjectRemoteID = [obj valueForKey:primaryKeyField];
        NSRange range = [relatedObjectRemoteID rangeOfString:@":nil"];
        if (range.location == NSNotFound) {
            NSManagedObjectID *sm_managedObjectID = [self newObjectIDForEntity:fetchRequest.entity referenceObject:relatedObjectRemoteID];
            
            // Allows us to always return object, faulted or not
            NSManagedObject *sm_managedObject = [context objectWithID:sm_managedObjectID];
            
            [results addObject:sm_managedObject];
        }
    }];
    
    return [NSArray arrayWithArray:results];
    
}

// Returns NSArray<NSManagedObject>
- (id)SM_fetchObjects:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError * __autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    if (SM_CACHE_ENABLED) {
        id resultsToReturn = nil;
        NSError *tempError = nil;
        switch ([self.coreDataStore cachePolicy]) {
            case SMCachePolicyTryNetworkOnly:
                if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch switch: SMCachePolicyTryNetworkOnly") }
                resultsToReturn = [self SM_fetchObjectsFromNetwork:fetchRequest withContext:context options:options error:error];
                break;
            case SMCachePolicyTryCacheOnly:
                if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch switch: SMCachePolicyTryCacheOnly") }
                resultsToReturn = [self SM_fetchObjectsFromCache:fetchRequest withContext:context error:error];
                break;
            case SMCachePolicyTryNetworkElseCache:
                if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch switch: SMCachePolicyTryNetworkElseCache") }
                resultsToReturn = [self SM_fetchObjectsFromNetwork:fetchRequest withContext:context options:options error:&tempError];
                if (tempError && [tempError code] == SMErrorNetworkNotReachable) {
                    resultsToReturn = [self SM_fetchObjectsFromCache:fetchRequest withContext:context error:error];
                }
                break;
            case SMCachePolicyTryCacheElseNetwork:
                if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch switch: SMCachePolicyTryCacheElseNetwork") }
                resultsToReturn = [self SM_fetchObjectsFromCache:fetchRequest withContext:context error:error];
                if (*error) {
                    return nil;
                }
                if ([resultsToReturn count] == 0) {
                    resultsToReturn = [self SM_fetchObjectsFromNetwork:fetchRequest withContext:context options:options error:error];
                }
                break;
            default:
                if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch switch: default") }
                if (error != NULL) {
                    NSError *errorToReturn = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorInvalidArguments userInfo:nil];
                    *error = (__bridge id)(__bridge_retained CFTypeRef)errorToReturn;
                }
                break;
        }
        
        if (SM_CORE_DATA_DEBUG) { DLog(@"Fetch results to return are %@ with error %@", resultsToReturn, *error) }
        return resultsToReturn;
    } else {
        id resultsToReturn = nil;
        resultsToReturn = [self SM_fetchObjectsFromNetwork:fetchRequest withContext:context options:options error:error];
        return resultsToReturn;
    }
}

// Returns NSArray<NSManagedObjectID>
- (id)SM_fetchObjectIDs:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context options:(SMRequestOptions *)options error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    NSFetchRequest *fetchCopy = [fetchRequest copy];
    
    [fetchCopy setResultType:NSManagedObjectResultType];
    
    if ([fetchRequest fetchBatchSize] > 0) {
        [fetchCopy setFetchBatchSize:[fetchRequest fetchBatchSize]];
    }
    
    NSArray *objects = [self SM_fetchObjects:fetchCopy withContext:context options:options error:error];
    
    // Error check
    if (*error != nil) {
        return nil;
    }
    
    return [objects map:^(id item) {
        return [item objectID];
    }];
}

////////////////////////////
#pragma mark - Incremental Store Methods
////////////////////////////

/*
 Returns an incremental store node encapsulating the persistent external values of the object with a given object ID.
 Return Value
 An incremental store node encapsulating the persistent external values of the object with object ID objectID, or nil if the corresponding object cannot be found.
 
 Discussion
 The returned node should include all attributes values and may include to-one relationship values as instances of NSManagedObjectID.
 
 If an object with object ID objectID cannot be found, the method should return nil and—if error is not NULL—create and return an appropriate error object in error.
 
 This method is used in 2 scenarios: When an object is fulfilling a fault, and before a save on updated objects to grab a copy from the server for merge conflict purposes.
 */
- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError *__autoreleasing *)error {
    
    if (SM_CORE_DATA_DEBUG) { DLog(@"new values for object with id %@", [context objectWithID:objectID]) }
    
    __block NSManagedObject *sm_managedObject = [context objectWithID:objectID];
    __block NSString *sm_managedObjectReferenceID = [self referenceObjectForObjectID:objectID];
    [self.coreDataStore.globalRequestOptions setTryRefreshToken:YES];
    
    if (SM_CACHE_ENABLED) {
        
        NSManagedObjectID *cacheObjectID = [self SM_retrieveCacheObjectForRemoteID:sm_managedObjectReferenceID entityName:[[sm_managedObject entity] name] createIfNeeded:NO];
        
        if (!cacheObjectID) {
            // Scenario: Got here because object was refreshed and is now a fault, but was never cached in the first place.  Grab from the server if possible.
            // NOTE: This may not be an issue with read + write cache
            
            if (SM_CORE_DATA_DEBUG) { DLog(@"Cache object id not found, need to pull from server if possible") }
            
            SMRequestOptions *optionsFromDictionary = [[[NSThread currentThread] threadDictionary] objectForKey:SMRequestSpecificOptions];
            SMRequestOptions *optionsForRequest = nil;
            if (self.isSaving) {
                if (optionsFromDictionary) {
                    optionsForRequest = [SMRequestOptions options];
                    [optionsForRequest setIsSecure:[optionsFromDictionary isSecure]];
                } else {
                    optionsForRequest = self.coreDataStore.globalRequestOptions;
                }
            } else {
                optionsForRequest = self.coreDataStore.globalRequestOptions;
            }
            NSDictionary *serializedObjectDict = [self SM_retrieveAndSerializeObjectWithID:sm_managedObjectReferenceID entity:[sm_managedObject entity] options:optionsForRequest context:context includeRelationships:NO cacheResult:!self.isSaving error:error];
            
            if (error != NULL && *error) {
                return nil;
            }
            
            SMIncrementalStoreNode *node = [[SMIncrementalStoreNode alloc] initWithObjectID:objectID withValues:serializedObjectDict version:1];
            
            return node;
            
        }
        
        NSManagedObject *objectFromCache = [self.localManagedObjectContext objectWithID:cacheObjectID];
        
        if (!objectFromCache) {
            [NSException raise:SMExceptionIncompatibleObject format:@"Cache object with managed object ID %@ not found.", cacheObjectID];
        }
        
        // Get primary key field of object
        NSString *primaryKeyField = nil;
        @try {
            primaryKeyField = [sm_managedObject primaryKeyField];
        }
        @catch (NSException *exception) {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Could not find primary key field for managed object, checking if user object") }
            if ([sm_managedObject isKindOfClass:[SMUserManagedObject class]]) {
                primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
                if (SM_CORE_DATA_DEBUG) { DLog(@"Object is user object, using userPrimaryKeyField as primary key") }
            }
        }
        
        // Check primary key, and if nil string is present we have an empty reference to a related object.  Need to grab values from the server if possible.
        NSString *cachePrimaryKey = [objectFromCache valueForKey:primaryKeyField];
        NSRange range = [cachePrimaryKey rangeOfString:@":nil"];
        if (range.location != NSNotFound) {
            
            // TODO possible to return error if network not available?
            SMRequestOptions *optionsFromDictionary = [[[NSThread currentThread] threadDictionary] objectForKey:SMRequestSpecificOptions];
            SMRequestOptions *optionsForRequest = nil;
            if (self.isSaving) {
                if (optionsFromDictionary) {
                    optionsForRequest = [SMRequestOptions options];
                    [optionsForRequest setIsSecure:[optionsFromDictionary isSecure]];
                } else {
                    optionsForRequest = self.coreDataStore.globalRequestOptions;
                }
            } else {
                optionsForRequest = self.coreDataStore.globalRequestOptions;
            }
            NSDictionary *serializedObjectDict = [self SM_retrieveAndSerializeObjectWithID:sm_managedObjectReferenceID entity:[sm_managedObject entity] options:optionsForRequest context:context includeRelationships:NO cacheResult:YES error:error];
            
            if (error != NULL && *error) {
                return nil;
            }
            
            SMIncrementalStoreNode *node = [[SMIncrementalStoreNode alloc] initWithObjectID:objectID withValues:serializedObjectDict version:1];
            
            return node;
            
        }
        
        // Create dictionary of keys and values for incremental store node
        NSMutableDictionary *dictionaryRepresentationOfCacheObject = [NSMutableDictionary dictionary];
        
        [[objectFromCache dictionaryWithValuesForKeys:[[[objectFromCache entity] attributesByName] allKeys]] enumerateKeysAndObjectsUsingBlock:^(id attributeName, id attributeValue, BOOL *stop) {
            if (attributeValue != [NSNull null]) {
                [dictionaryRepresentationOfCacheObject setObject:attributeValue forKey:attributeName];
            }
        }];
        
        [[objectFromCache dictionaryWithValuesForKeys:[[[objectFromCache entity] relationshipsByName] allKeys]] enumerateKeysAndObjectsUsingBlock:^(id relationshipName, id relationshipValue, BOOL *stop) {
            if (![[[[objectFromCache entity] relationshipsByName] objectForKey:relationshipName] isToMany]) {
                if (relationshipValue == [NSNull null] || relationshipValue == nil) {
                    [dictionaryRepresentationOfCacheObject setObject:[NSNull null] forKey:relationshipName];
                } else {
                    
                    NSString *referenceObjectForDictionary = [self SM_getRemoteIDForCacheManagedObjectID:[relationshipValue objectID]];
                    NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationshipValue entity] referenceObject:referenceObjectForDictionary];
                    [dictionaryRepresentationOfCacheObject setObject:relationshipObjectID forKey:relationshipName];
                }
            }
        }];
        
        
        SMIncrementalStoreNode *node = [[SMIncrementalStoreNode alloc] initWithObjectID:objectID withValues:dictionaryRepresentationOfCacheObject version:1];
        
        return node;
        
        /*
        // If the object is not faulted, values are in memory but core data is requesting persistent store values.
        
        NSDictionary *serializedObjectDictionary = nil;
        
        // If the context's merge policy is that in memory wins, we do not need to make a network call to retreive persisted values.
        if ([context mergePolicy] == NSMergeByPropertyObjectTrumpMergePolicy) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[sm_managedObject dictionaryWithValuesForKeys:[[[sm_managedObject entity] attributesByName] allKeys]]];
            NSDictionary *relationships = [[sm_managedObject entity] relationshipsByName];
            [relationships enumerateKeysAndObjectsUsingBlock:^(id relationshipName, id relationshipDescription, BOOL *stop) {
                if (![relationshipDescription isToMany]) {
                    if ([sm_managedObject valueForKey:relationshipName] != nil) {
                        [dict setObject:[[sm_managedObject valueForKey:relationshipName] objectID] forKey:relationshipName];
                    } else {
                        [dict setObject:[NSNull null] forKey:relationshipName];
                    }
                    
                }
            }];
            serializedObjectDictionary = [NSDictionary dictionaryWithDictionary:dict];
        } else {
            serializedObjectDictionary = [self SM_retrieveAndSerializeObjectWithID:sm_managedObjectReferenceID entity:[sm_managedObject entity] options:[SMRequestOptions options] context:context includeRelationships:NO cacheResult:NO error:error];
            
            if (!serializedObjectDictionary) {
                return nil;
            }
        }
        
        SMIncrementalStoreNode *node = [[SMIncrementalStoreNode alloc] initWithObjectID:objectID withValues:serializedObjectDictionary version:1];
        
        return node;
         */
        
    } else {
        
        // Cache is not enabled, must read from server if possible
        
        SMRequestOptions *optionsFromDictionary = [[[NSThread currentThread] threadDictionary] objectForKey:SMRequestSpecificOptions];
        SMRequestOptions *optionsForRequest = nil;
        if (self.isSaving) {
            if (optionsFromDictionary) {
                optionsForRequest = [SMRequestOptions options];
                [optionsForRequest setIsSecure:[optionsFromDictionary isSecure]];
            } else {
                optionsForRequest = self.coreDataStore.globalRequestOptions;
            }
        } else {
            optionsForRequest = self.coreDataStore.globalRequestOptions;
        }
        NSDictionary *serializedObjectDictionary = [self SM_retrieveAndSerializeObjectWithID:sm_managedObjectReferenceID entity:[sm_managedObject entity] options:optionsForRequest context:context includeRelationships:NO cacheResult:NO error:error];
        
        SMIncrementalStoreNode *node = [[SMIncrementalStoreNode alloc] initWithObjectID:objectID withValues:serializedObjectDictionary version:1];
        
        return node;
        
    } // end if/else SM_CACHE_ENABLED
    
}

- (NSString *)SM_getRemoteIDForCacheManagedObjectID:(NSManagedObjectID *)cacheManagedObjectID
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSString *entityName = [[cacheManagedObjectID entity] name];
    NSString *stringRepOfRelationshipCacheID = [[cacheManagedObjectID URIRepresentation] absoluteString];
    NSArray *components = [stringRepOfRelationshipCacheID componentsSeparatedByString:[NSString stringWithFormat:@"%@/", entityName]];
    
    NSString *cacheMapReference = [components lastObject];
    
    NSDictionary *remoteIDsForEntity = [self.cacheMappingTable objectForKey:entityName];
    
    if (!remoteIDsForEntity) {
        // TODO add error
    }
    
    NSArray *allKeysForObject = [remoteIDsForEntity allKeysForObject:cacheMapReference];
    if ([allKeysForObject count] != 1) {
        [NSException raise:SMExceptionIncompatibleObject format:@"Multiple or no keys for cache map reference %@, entity %@.  Please submit a support ticket with StackMob.", cacheMapReference, entityName];
    }

    return [allKeysForObject lastObject];
}

/*
 Return Value
 The value of the relationship specified relationship of the object with object ID objectID, or nil if an error occurs.
 
 Discussion
 If the relationship is a to-one, the method should return an NSManagedObjectID instance that identifies the destination, or an instance of NSNull if the relationship value is nil.
 
 If the relationship is a to-many, the method should return a collection object containing NSManagedObjectID instances to identify the related objects. Using an NSArray instance is preferred because it will be the most efficient. A store may also return an instance of NSSet or NSOrderedSet; an instance of NSDictionary is not acceptable.
 
 If an object with object ID objectID cannot be found, the method should return nil and—if error is not NULL—create and return an appropriate error object in error.
 */

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) {DLog()}
    [self.coreDataStore.globalRequestOptions setTryRefreshToken:YES];
    
    id result = nil;
    @try {
        result = [self SM_newValueForRelationship:relationship forObjectWithID:objectID withContext:context error:error];
    }
    @catch (NSException *exception) {
        if  ([exception name] != SMExceptionCannotFillRelationshipFault) {
            [NSException raise:[exception name] format:@"%@", [exception reason]];
        }
        if (NULL != error) {
            *error = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorCouldNotFillRelationshipFault userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"Cannot fill relationship %@ fault for object ID %@, related object not cached and network is not reachable", [relationship name], objectID], NSLocalizedDescriptionKey, nil]];
            *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
        }
        return nil;
    }
    
    return result;
    
    
}
- (id)SM_newValueForRelationship:(NSRelationshipDescription *)relationship
                 forObjectWithID:(NSManagedObjectID *)objectID
                     withContext:(NSManagedObjectContext *)context
                           error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog(@"new value for relationship %@ for object with id %@", relationship, objectID) }
    
    __block NSManagedObject *sm_managedObject = [context objectWithID:objectID];
    __block NSString *sm_managedObjectReferenceID = [self referenceObjectForObjectID:objectID];
    
    if (SM_CACHE_ENABLED) {
        
        // Retreive parent object from cache
        NSManagedObjectID *cacheObjectID = [self SM_retrieveCacheObjectForRemoteID:sm_managedObjectReferenceID entityName:[[sm_managedObject entity] name] createIfNeeded:NO];
        if (!cacheObjectID) {
            // TODO handle error
        }
        NSManagedObject *objectFromCache = [self.localManagedObjectContext objectWithID:cacheObjectID];
        
        // Get primary key field of relationship
        NSString *primaryKeyField = nil;
        @try {
            primaryKeyField = [[relationship destinationEntity] primaryKeyField];
        }
        @catch (NSException *exception) {
            primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
        }
        
        if ([relationship isToMany]) {
            // to-many: pull related object set from cache
            // value should be the cache object reference for the related object, if the relationship value is not nil
            
            NSArray *relatedObjectCacheReferenceSet = [[objectFromCache valueForKey:[relationship name]] allObjects];
            if ([relatedObjectCacheReferenceSet count] == 0) {
                return [NSArray array];
            }
            __block NSMutableArray *arrayToReturn = [NSMutableArray array];
            __block BOOL shouldRetreiveFromNetwork = NO;
            
            [relatedObjectCacheReferenceSet enumerateObjectsUsingBlock:^(id cacheManagedObject, NSUInteger idx, BOOL *stop) {
                
                // If primary key includes the nil string, this was just a reference and we need to retreive online, if possible
                NSString *relatedObjectRemoteID = [cacheManagedObject valueForKey:primaryKeyField];
                NSRange range = [relatedObjectRemoteID rangeOfString:@":nil"];
                if (range.location != NSNotFound) {
                    // All objects are likely references, retreive object online if possible
                    shouldRetreiveFromNetwork = YES;
                    *stop = YES;
                } else {
                    // Use primary key id to create in-memory context managed object ID equivalent
                    NSManagedObjectID *sm_managedObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:relatedObjectRemoteID];
                    
                    [arrayToReturn addObject:sm_managedObjectID];
                }
                
            }];
            
            if (shouldRetreiveFromNetwork) {
                [arrayToReturn removeAllObjects];
                // TODO add per-request options?
                SMRequestOptions *optionsForRetrieval = self.coreDataStore.globalRequestOptions;
                id resultToReturn =  [self SM_retrieveAndCacheRelatedObjectForRelationship:relationship parentObject:sm_managedObject referenceID:sm_managedObjectReferenceID options:optionsForRetrieval context:context error:error];
                arrayToReturn = resultToReturn;
            }
            
            return arrayToReturn;
            
        } else {
            // to-one: pull related object from cache
            // value should be the cache object reference for the related object, if the relationship value is not nil
            NSManagedObject *relatedObjectCacheReferenceObject = [objectFromCache valueForKey:[relationship name]];
            if (!relatedObjectCacheReferenceObject) {
                return [NSNull null];
            } else {
                // If primary key includes the nil string, this was just a reference and we need to retreive online, if possible
                NSString *relatedObjectRemoteID = [relatedObjectCacheReferenceObject valueForKey:primaryKeyField];
                NSRange range = [relatedObjectRemoteID rangeOfString:@":nil"];
                if (range.location != NSNotFound) {
                    // Retreive object from server
                    // TODO pull per-request options?
                    SMRequestOptions *optionsForRetrival = self.coreDataStore.globalRequestOptions;
                    id resultToReturn =  [self SM_retrieveAndCacheRelatedObjectForRelationship:relationship parentObject:sm_managedObject referenceID:sm_managedObjectReferenceID options:optionsForRetrival context:context error:error];
                    return resultToReturn;
                }
                
                // Use primary key id to create in-memory context managed object ID equivalent
                NSManagedObjectID *sm_managedObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:relatedObjectRemoteID];
                
                return sm_managedObjectID;
            }
        }
        
        /*
        if (!self.isSaving && [sm_managedObject hasFaultForRelationshipNamed:[relationship name]]) {
         
         
        }
    
        // If the object is not faulted, core data is requesting values from persistent store and we need to retreive an up-to-date copy from the server.
        
        id result = nil;
        
        // If the context's merge policy is that client wins, we do not need to make a network call to retreive persisted values.
        //if ([self.coreDataStore cacheIsEnabled] && [context mergePolicy] == NSMergeByPropertyObjectTrumpMergePolicy) {
        if ([context mergePolicy] == NSMergeByPropertyObjectTrumpMergePolicy) {
            if ([relationship isToMany]) {
                result = [NSArray array];
            } else {
                result = [NSNull null];
            }
        } else {
            // Retreive object from server
            SMRequestOptions *optionsFromDictionary = [[[NSThread currentThread] threadDictionary] objectForKey:SMRequestSpecificOptions];
            SMRequestOptions *optionsForRequest = nil;
            if (self.isSaving) {
                if (optionsFromDictionary) {
                    optionsForRequest = [SMRequestOptions options];
                    [optionsForRequest setIsSecure:[optionsFromDictionary isSecure]];
                } else {
                    optionsForRequest = self.coreDataStore.globalRequestOptions;
                }
            } else {
                optionsForRequest = self.coreDataStore.globalRequestOptions;
            }
            result = [self SM_retrieveRelatedObjectForRelationship:relationship parentObject:sm_managedObject referenceID:sm_managedObjectReferenceID options:optionsForRequest context:context error:error];
        }
        
        
        return result;
         */
        
    } else {
        
        // Cache is not enabled, read from server if possible
        
        id result = nil;
        SMRequestOptions *optionsFromDictionary = [[[NSThread currentThread] threadDictionary] objectForKey:SMRequestSpecificOptions];
        SMRequestOptions *optionsForRequest = nil;
        if (self.isSaving) {
            if (optionsFromDictionary) {
                optionsForRequest = [SMRequestOptions options];
                [optionsForRequest setIsSecure:[optionsFromDictionary isSecure]];
            } else {
                optionsForRequest = self.coreDataStore.globalRequestOptions;
            }
        } else {
            optionsForRequest = self.coreDataStore.globalRequestOptions;
        }
        result = [self SM_retrieveRelatedObjectForRelationship:relationship parentObject:sm_managedObject referenceID:sm_managedObjectReferenceID options:optionsForRequest context:context error:error];
        
        return result;
        
    } // end if/else SM_CACHE_ENABLED
    
}

/*
 Returns an array containing the object IDs for a given array of newly-inserted objects.
 This method is called before executeRequest:withContext:error: with a save request, to assign permanent IDs to newly-inserted objects.
 */
- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array
                                    error:(NSError *__autoreleasing *)error {
    if (SM_CORE_DATA_DEBUG) { DLog(@"obtain permanent ids for objects: %@", truncateOutputIfExceedsMaxLogLength(array)) }
    // check if array is null, return empty array if so
    if (array == nil) {
        return [NSArray array];
    }
    
    if (*error) {
        if (SM_CORE_DATA_DEBUG) { DLog(@"error with obtaining perm ids is %@", *error) }
        *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
    }
    
    return [array map:^id(id item) {
        NSString *itemId = [item SMObjectId];
        if (!itemId) {
            [NSException raise:SMExceptionIncompatibleObject format:@"Item not previously assigned an object ID for it's primary key field, which is used to obtain a permanent ID for the Core Data object.  Before a call to save on the managedObjectContext, be sure to assign an object ID.  This looks something like [newManagedObject setValue:[newManagedObject assignObjectId] forKey:[newManagedObject primaryKeyField]].  The item in question is %@", item];
        }
        
        NSManagedObjectID *returnId = [self newObjectIDForEntity:[item entity] referenceObject:itemId];
        if (SM_CORE_DATA_DEBUG) { DLog(@"Permanent ID assigned is %@", returnId) }
        
        return returnId;
    }];
}

////////////////////////////
#pragma mark - Local Cache Configuration
////////////////////////////

- (void)SM_configureCache
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    _localManagedObjectModel = self.localManagedObjectModel;
    _localManagedObjectContext = self.localManagedObjectContext;
    _localPersistentStoreCoordinator = self.localPersistentStoreCoordinator;
    [self SM_readCacheMap];
    [self SM_readDirtyQueue];
    if (SM_CORE_DATA_DEBUG) {DLog(@"STACKMOB SYSTEM UPDATE: Cache initialized and ready to go.")}
    
}

- (NSManagedObjectModel *)localManagedObjectModel
{
    if (_localManagedObjectModel == nil) {
        _localManagedObjectModel = self.persistentStoreCoordinator.managedObjectModel;
    }
    
    return _localManagedObjectModel;
}

- (NSManagedObjectContext *)localManagedObjectContext
{
    if (_localManagedObjectContext == nil) {
        _localManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [_localManagedObjectContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        [_localManagedObjectContext setPersistentStoreCoordinator:self.localPersistentStoreCoordinator];
    }
    
    return _localManagedObjectContext;
    
}

- (NSPersistentStoreCoordinator *)localPersistentStoreCoordinator
{
    if (_localPersistentStoreCoordinator == nil) {
        
        _localPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.localManagedObjectModel];
        
        NSURL *storeURL = [self SM_getStoreURLForFileComponent:SQL_DB];
        [self SM_createStoreURLPathIfNeeded:storeURL];
        
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
        
        NSError *error = nil;
        [_localPersistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
        
        if (error != nil) {
            [NSException raise:SMExceptionAddPersistentStore format:@"Error creating sqlite persistent store: %@", error];
        }
        
    }
    
    return _localPersistentStoreCoordinator;
}

- (NSURL *)SM_getStoreURLForFileComponent:(NSString *)fileComponent
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSString *applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey:(NSString *)kCFBundleNameKey];
    NSString *applicationDocumentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *applicationStorageDirectory = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:applicationName];
    
    NSString *fullFileName = nil;
    if (applicationName != nil)
    {
        fullFileName = [NSString stringWithFormat:@"%@-%@-%@", applicationName, self.coreDataStore.session.regularOAuthClient.publicKey, fileComponent];
    } else {
        fullFileName = [NSString stringWithFormat:@"%@-%@", self.coreDataStore.session.regularOAuthClient.publicKey, fileComponent];
    }
    
    
    NSArray *paths = [NSArray arrayWithObjects:applicationDocumentsDirectory, applicationStorageDirectory, nil];
    
    NSFileManager *fm = [[NSFileManager alloc] init];
    
    for (NSString *path in paths)
    {
        NSString *filepath = [path stringByAppendingPathComponent:fullFileName];
        if ([fm fileExistsAtPath:filepath])
        {
            return [NSURL fileURLWithPath:filepath];
        }
        
    }
    
    NSURL *aURL = [NSURL fileURLWithPath:[applicationStorageDirectory stringByAppendingPathComponent:fullFileName]];
    return aURL;
}

- (void)SM_createStoreURLPathIfNeeded:(NSURL *)storeURL
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *pathToStore = [storeURL URLByDeletingLastPathComponent];
    BOOL isDir;
    BOOL fileExists = [fileManager fileExistsAtPath:[pathToStore path] isDirectory:&isDir];
    if (!fileExists) {
        NSError *error = nil;
        BOOL pathWasCreated = [fileManager createDirectoryAtPath:[pathToStore path] withIntermediateDirectories:YES attributes:nil error:&error];
        
        if (!pathWasCreated) {
            [NSException raise:SMExceptionAddPersistentStore format:@"Error creating sqlite persistent store: %@", error];
        }
    }
    
}

- (void)SM_removeStoreURLPath:(NSURL *)storeURL
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[storeURL path]]) {
        NSError *deleteError = nil;
        BOOL delete = [fileManager removeItemAtURL:storeURL error:&deleteError];
        if (!delete) {
            [NSException raise:@"SMExceptionCouldNotDeleteSQLiteDatabase" format:@""];
        }
    }
}

- (void)SM_readCacheMap
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSURL *mapPath = [self SM_getStoreURLForFileComponent:CACHE_MAP_FILE];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[mapPath path]]) {
        NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:[mapPath path]];
        NSDictionary *temp = (NSDictionary *)[NSPropertyListSerialization
                                              propertyListFromData:plistXML
                                              mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                              format:&format
                                              errorDescription:&errorDesc];
        
        if (!temp) {
            [NSException raise:SMExceptionCacheError format:@"Error reading cachemap: %@, format: %ld", errorDesc, (unsigned long)format];
        } else {
            self.cacheMappingTable = [temp mutableCopy];
        }
    } else {
        self.cacheMappingTable = [NSMutableDictionary dictionary];
    }
}

- (void)SM_saveCacheMap
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSString *errorDesc = nil;
    NSError *error = nil;
    NSURL *mapPath = [self SM_getStoreURLForFileComponent:CACHE_MAP_FILE];
    
    NSData *mapData = [NSPropertyListSerialization dataFromPropertyList:self.cacheMappingTable
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                       errorDescription:&errorDesc];
    
    if (!mapData) {
        [NSException raise:SMExceptionCacheError format:@"Error serializing cachemap data with error description %@", errorDesc];
    }
    
    BOOL successfulWrite = [mapData writeToFile:[mapPath path] options:NSDataWritingAtomic error:&error];
    if (!successfulWrite) {
        [NSException raise:SMExceptionCacheError format:@"Error saving cachemap data with error %@", error];
    }
    
}

- (void)SM_readDirtyQueue
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSURL *mapPath = [self SM_getStoreURLForFileComponent:DIRTY_QUEUE_FILE];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[mapPath path]]) {
        NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:[mapPath path]];
        NSDictionary *temp = (NSDictionary *)[NSPropertyListSerialization
                                              propertyListFromData:plistXML
                                              mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                              format:&format
                                              errorDescription:&errorDesc];
        
        if (!temp) {
            [NSException raise:SMExceptionCacheError format:@"Error reading dirty queue file: %@, format: %ld", errorDesc, (unsigned long)format];
        } else {
            self.dirtyQueue = [temp mutableCopy];
        }
    } else {
        self.dirtyQueue = [NSMutableDictionary dictionary];
        [self.dirtyQueue setObject:[NSArray array] forKey:@"inserted"];
        [self.dirtyQueue setObject:[NSArray array] forKey:@"updated"];
        [self.dirtyQueue setObject:[NSArray array] forKey:@"deleted"];
    }
}

- (void)SM_saveDirtyQueue
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSString *errorDesc = nil;
    NSError *error = nil;
    NSURL *mapPath = [self SM_getStoreURLForFileComponent:DIRTY_QUEUE_FILE];
    
    NSData *mapData = [NSPropertyListSerialization dataFromPropertyList:self.dirtyQueue
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                       errorDescription:&errorDesc];
    
    if (!mapData) {
        [NSException raise:SMExceptionCacheError format:@"Error serializing dirty queue data with error description %@", errorDesc];
    }
    
    BOOL successfulWrite = [mapData writeToFile:[mapPath path] options:NSDataWritingAtomic error:&error];
    if (!successfulWrite) {
        [NSException raise:SMExceptionCacheError format:@"Error saving dirty queue data with error %@", error];
    }
    
}

////////////////////////////
#pragma mark - Local Cache Operations
////////////////////////////

- (void)SM_cacheObjects:(NSArray *)objectsToBeCached
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    
    if (SM_CACHE_ENABLED) {
        [objectsToBeCached enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [self SM_cacheObjectWithID:obj[0] values:obj[1] entity:obj[2] context:obj[3]];
        }];
    }
}

- (NSDictionary *)SM_retrieveAndSerializeObjectWithID:(NSString *)objectID entity:(NSEntityDescription *)entity options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context includeRelationships:(BOOL)includeRelationships cacheResult:(BOOL)cacheResult error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSDictionary *serializedObjectDictionary = nil;
    NSDictionary *objectFromServer = [self SM_retrieveObjectWithID:objectID entity:entity options:options context:context error:error];
    
    if (!objectFromServer) {
        return nil;
    }
    
    if (cacheResult) {
        [self SM_cacheObjectWithID:objectID values:objectFromServer entity:entity context:context];
        [self SM_saveCache:NULL];
    }
    
    serializedObjectDictionary = [self SM_responseSerializationForDictionary:objectFromServer schemaEntityDescription:entity managedObjectContext:context includeRelationships:includeRelationships];
    
    return serializedObjectDictionary;
}

- (NSDictionary *)SM_retrieveObjectWithID:(NSString *)objectID entity:(NSEntityDescription *)entity options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block NSEntityDescription *sm_managedObjectEntity = entity;
    __block NSString *schemaName = [[sm_managedObjectEntity name] lowercaseString];
    __block BOOL readSuccess = NO;
    __block NSDictionary *objectFromServer;
    __block NSError *blockError = nil;
    
    // create a group dispatch and queue
    dispatch_queue_t queue = dispatch_queue_create("Retrieve Object From Server Queue", NULL);
    dispatch_group_t group = dispatch_group_create();
    
    dispatch_group_enter(group);
    [self.coreDataStore readObjectWithId:objectID inSchema:schemaName options:options successCallbackQueue:queue failureCallbackQueue:queue onSuccess:^(NSDictionary *theObject, NSString *schema) {
        objectFromServer = theObject;
        readSuccess = YES;
        dispatch_group_leave(group);
    } onFailure:^(NSError *theError, NSString *theObjectId, NSString *schema) {
        if (SM_CORE_DATA_DEBUG) { DLog(@"Could not read the object with objectId %@ and error userInfo %@", theObjectId, [theError userInfo]) }
        readSuccess = NO;
        blockError = theError;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    if (!readSuccess) {
        if (NULL != error) {
            *error = [[NSError alloc] initWithDomain:[blockError domain] code:[blockError code] userInfo:[blockError userInfo]];
            *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
        }
        return nil;
    }
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(group);
    dispatch_release(queue);
#endif
    
    return objectFromServer;
    
}

- (id)SM_retrieveRelatedObjectForRelationship:(NSRelationshipDescription *)relationship parentObject:(NSManagedObject *)parentObject referenceID:(NSString *)referenceID options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block NSEntityDescription *sm_managedObjectEntity = [parentObject entity];
    // No expansion,
    __block NSDictionary *objectDictionaryFromRead = [self SM_retrieveObjectWithID:referenceID entity:sm_managedObjectEntity options:options context:context error:error];
    
    if (!objectDictionaryFromRead) {
        return nil;
    }
    
    id relationshipContents = [objectDictionaryFromRead valueForKey:[sm_managedObjectEntity SMFieldNameForProperty:relationship]];
    
    if ([relationship isToMany]) {
        if (relationshipContents) {
            if (![relationshipContents isKindOfClass:[NSArray class]]) {
                [NSException raise:SMExceptionIncompatibleObject format:@"Relationship contents should be an array for a to-many relationship. The relationship passed has contents that are of class type %@. Confirm that this relationship was meant to be to-many.", [relationshipContents class]];
            }
            NSMutableArray *arrayToReturn = [NSMutableArray array];
            [(NSSet *)relationshipContents enumerateObjectsUsingBlock:^(id stringIdReference, BOOL *stop) {
                NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:stringIdReference];
                [arrayToReturn addObject:relationshipObjectID];
            }];
            return  arrayToReturn;
        } else {
            return [NSArray array];
        }
    } else {
        if (relationshipContents) {
            if (![relationshipContents isKindOfClass:[NSString class]]) {
                [NSException raise:SMExceptionIncompatibleObject format:@"Relationship contents should be a string for a to-one relationship. The relationship passed has contents that are of class type %@. Confirm that this relationship was meant to be to-one.", [relationshipContents class]];
            }
            NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:relationshipContents];
            return relationshipObjectID;
        } else {
            return [NSNull null];
        }
    }
}

- (id)SM_retrieveAndCacheRelatedObjectForRelationship:(NSRelationshipDescription *)relationship parentObject:(NSManagedObject *)parentObject referenceID:(NSString *)referenceID options:(SMRequestOptions *)options context:(NSManagedObjectContext *)context error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block NSEntityDescription *sm_managedObjectEntity = [parentObject entity];
    __block NSDictionary *objectDictionaryFromRead = nil;
    __block NSString *sm_fieldName = [sm_managedObjectEntity SMFieldNameForProperty:relationship];
    
    // TODO support global expand depth functionality
    [options setExpandDepth:1];
    objectDictionaryFromRead = [self SM_retrieveObjectWithID:referenceID entity:sm_managedObjectEntity options:options context:context error:error];
    NSMutableDictionary *headersCopy = [[options headers] mutableCopy];
    [headersCopy removeObjectForKey:@"X-StackMob-Expand"];
    [options setHeaders:[NSDictionary dictionaryWithDictionary:headersCopy]];
    
    if (!objectDictionaryFromRead) {
        return nil;
    }
    
    // purge cache of parent object existing relationships in cache, to be replaced by object dictionary from read
    // TODO replace entire object in cache, including relationships
    
    // Fetch Parent Cache Object
    NSManagedObjectID *cacheParentObjectID = [self SM_retrieveCacheObjectForRemoteID:referenceID entityName:[[parentObject entity] name] createIfNeeded:NO];
    NSManagedObject *cacheParentObject = [self.localManagedObjectContext objectWithID:cacheParentObjectID];

    id relationshipContents = [objectDictionaryFromRead valueForKey:sm_fieldName];
    
    if ([relationship isToMany]) {
        
        // Purge relationship from cacheParentObject 
        [self SM_purgeCacheManagedObjectsFromCache:[cacheParentObject valueForKey:[relationship name]]];
        
        /*
        NSSet *relationshipContentsFromCache = [cacheParentObject valueForKey:[relationship name]];
        __block NSMutableArray *cacheObjectsToBePurged = [NSMutableArray array];
        [relationshipContentsFromCache enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            [cacheObjectsToBePurged addObject:obj];
        }];
        [self SM_purgeCacheManagedObjectsFromCache:cacheObjectsToBePurged];
         */
        
        // Using NSObject here as NSMutableSet and NSMutableOrderedSet don't share a mutable base class
        // By doing this and casting in the right place we avoid having to duplicate a lot of code
        __block NSObject *newRelationshipContents = nil;
        if ([relationship isOrdered]) {
            newRelationshipContents = [cacheParentObject mutableOrderedSetValueForKey:[relationship name]];
            [(NSMutableOrderedSet *)newRelationshipContents removeAllObjects];
        } else {
            newRelationshipContents = [cacheParentObject mutableSetValueForKey:[relationship name]];
            [(NSMutableSet *)newRelationshipContents removeAllObjects];
        }
        
        if (relationshipContents) {
            // Cache and relate new objects
            if (![relationshipContents isKindOfClass:[NSArray class]]) {
                [NSException raise:SMExceptionIncompatibleObject format:@"Relationship contents should be an array for a to-many relationship. The relationship passed has contents that are of class type %@. Confirm that this relationship was meant to be to-many.", [relationshipContents class]];
            }
            __block NSMutableArray *arrayToReturn = [NSMutableArray array];
            [(NSArray *)relationshipContents enumerateObjectsUsingBlock:^(id expandedObject, NSUInteger idx, BOOL *stop) {
                NSString *relatedObjectPrimaryKey = [expandedObject objectForKey:[[relationship destinationEntity] SMPrimaryKeyField]];
                NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:relatedObjectPrimaryKey];
                [arrayToReturn addObject:relationshipObjectID];
                
                // Cache object
                [self SM_cacheObjectWithID:relatedObjectPrimaryKey values:expandedObject entity:[relationship destinationEntity] context:context];

                NSManagedObject *newlyCachedObject = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:relatedObjectPrimaryKey entityName:[[relationship destinationEntity] name] createIfNeeded:YES]];
                
                if ([relationship isOrdered]) {
                    [(NSMutableOrderedSet *)newRelationshipContents addObject:newlyCachedObject];
                } else {
                    [(NSMutableSet *)newRelationshipContents addObject:newlyCachedObject];
                }
            }];
            
            [self SM_saveCache:error];
            
            return arrayToReturn;
            
        } else {
            // Save empty array
            [self SM_saveCache:error];
            return [NSArray array];
        }
    } else {
        
        NSManagedObject *relationshipContentsFromCache = [cacheParentObject valueForKey:[relationship name]];
        if (relationshipContentsFromCache) {
            [self SM_purgeCacheManagedObjectFromCache:relationshipContentsFromCache];
        }
        
        if (relationshipContents) {
            if (![relationshipContents isKindOfClass:[NSDictionary class]]) {
                [NSException raise:SMExceptionIncompatibleObject format:@"Relationship contents should be a Dictionary for a to-one relationship with expansion. The relationship passed has contents that are of class type %@. Confirm that this relationship was meant to be to-one.", [relationshipContents class]];
            }
            NSString *relatedObjectPrimaryKey = [relationshipContents objectForKey:[[relationship destinationEntity] primaryKeyField]];
            NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationship destinationEntity] referenceObject:relatedObjectPrimaryKey];
            
            [self SM_cacheObjectWithID:relatedObjectPrimaryKey values:relationshipContents entity:[relationship destinationEntity] context:context];
            NSManagedObject *newlyCachedObject = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:relatedObjectPrimaryKey entityName:[[relationship destinationEntity] name] createIfNeeded:YES]];
            [cacheParentObject setValue:newlyCachedObject forKey:[relationship name]];
            // Save Cache if has changes
            [self SM_saveCache:error];
            
            return relationshipObjectID;
        } else {
            // Save Cache if has changes
            [self SM_saveCache:error];
            return [NSNull null];
        }
    }
    
}

- (void)SM_cacheObjectWithID:(NSString *)objectID values:(NSDictionary *)values entity:(NSEntityDescription *)entity context:(NSManagedObjectContext *)context
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    // Get cached managed object or create if needed
    NSManagedObject *cacheManagedObject = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:objectID entityName:[entity name] createIfNeeded:YES]];
    
    // Serialize expanded object with relationships
    NSDictionary *serializedObjectDict = [self SM_responseSerializationForDictionary:values schemaEntityDescription:entity managedObjectContext:context includeRelationships:YES];
    
    // Populate cached object
    [self SM_populateCacheManagedObject:cacheManagedObject withDictionary:serializedObjectDict entity:entity];
}

- (void)SM_populateManagedObject:(NSManagedObject *)object withDictionary:(NSDictionary *)dictionary entity:(NSEntityDescription *)entity
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    // Enumerate through properties and set internal storage
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id propertyName, id propertyValue, BOOL *stop) {
        NSPropertyDescription *propertyDescription = [[entity propertiesByName] objectForKey:propertyName];
        if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {
            [object setPrimitiveValue:dictionary[propertyName] forKey:propertyName];
        } else if (![object hasFaultForRelationshipNamed:propertyName]) {
            NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)propertyDescription;
            if ([relationshipDescription isToMany]) {
                NSMutableSet *relatedObjects = [[object primitiveValueForKey:propertyName] mutableCopy];
                if (relatedObjects != nil) {
                    [relatedObjects removeAllObjects];
                    NSSet *serializedDictSet = dictionary[propertyName];
                    [serializedDictSet enumerateObjectsUsingBlock:^(id managedObjectID, BOOL *stopEnum) {
                        [relatedObjects addObject:[[object managedObjectContext] objectWithID:managedObjectID]];
                    }];
                    [object setPrimitiveValue:relatedObjects forKey:propertyName];
                }
            } else {
                if (dictionary[propertyName] == [NSNull null]) {
                    [object setPrimitiveValue:nil forKey:propertyName];
                } else {
                    NSManagedObject *toOneObject = [[object managedObjectContext] objectWithID:dictionary[propertyName]];
                    [object setPrimitiveValue:toOneObject forKey:propertyName];
                }
            }
        }
    }];
    
}

- (void)SM_populateCacheManagedObject:(NSManagedObject *)object withDictionary:(NSDictionary *)dictionary entity:(NSEntityDescription *)entity
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    [[entity propertiesByName] enumerateKeysAndObjectsUsingBlock:^(id propertyName, id property, BOOL *stop) {
        id propertyValueFromSerializedDict = [dictionary objectForKey:propertyName];
        if (propertyValueFromSerializedDict == [NSNull null]) {
            [object setValue:nil forKey:propertyName];
        } else if (propertyValueFromSerializedDict) {
            if ([property isKindOfClass:[NSAttributeDescription class]]) {
                [object setValue:propertyValueFromSerializedDict forKey:propertyName];
            } else if ([(NSRelationshipDescription *)property isToMany]) {
                
                if ([(NSRelationshipDescription *)property isOrdered]) {
                    __block NSMutableOrderedSet *objectRelationshipSet = nil;
                    objectRelationshipSet = [object mutableOrderedSetValueForKey:propertyName];
                    [objectRelationshipSet removeAllObjects];
                    [(NSSet *)propertyValueFromSerializedDict enumerateObjectsUsingBlock:^(id obj, BOOL *stopEnum) {
                        NSManagedObject *objectToAdd = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:[self referenceObjectForObjectID:obj] entityName:[[property destinationEntity] name] createIfNeeded:YES]];
                        
                        NSString *objectToAddPrimaryKey = nil;
                        if ([[[[property destinationEntity] name] lowercaseString] isEqualToString:[self.coreDataStore.session userSchema]]) {
                            objectToAddPrimaryKey = [self.coreDataStore.session userPrimaryKeyField];
                        } else {
                            objectToAddPrimaryKey = [[property destinationEntity] primaryKeyField];
                        }
                        
                        if (![objectToAdd valueForKey:objectToAddPrimaryKey]) {
                            // Add a flag if this is a relationship reference
                            [objectToAdd setValue:[NSString stringWithFormat:@"%@:nil", [self referenceObjectForObjectID:obj]] forKey:[objectToAdd primaryKeyField]];
                        }
                        [objectRelationshipSet addObject:objectToAdd];
                        
                    }];
                } else {
                    __block NSMutableSet *objectRelationshipSet = nil;
                    objectRelationshipSet = [object mutableSetValueForKey:propertyName];
                    [objectRelationshipSet removeAllObjects];
                    [(NSSet *)propertyValueFromSerializedDict enumerateObjectsUsingBlock:^(id obj, BOOL *stopEnum) {
                        NSManagedObject *objectToAdd = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:[self referenceObjectForObjectID:obj] entityName:[[property destinationEntity] name] createIfNeeded:YES]];
                        
                        NSString *objectToAddPrimaryKey = nil;
                        if ([[[[property destinationEntity] name] lowercaseString] isEqualToString:[self.coreDataStore.session userSchema]]) {
                            objectToAddPrimaryKey = [self.coreDataStore.session userPrimaryKeyField];
                        } else {
                            objectToAddPrimaryKey = [[property destinationEntity] primaryKeyField];
                        }
                        
                        if (![objectToAdd valueForKey:objectToAddPrimaryKey]) {
                            // Add a flag if this is a relationship reference
                            [objectToAdd setValue:[NSString stringWithFormat:@"%@:nil", [self referenceObjectForObjectID:obj]] forKey:[objectToAdd primaryKeyField]];
                        }
                        [objectRelationshipSet addObject:objectToAdd];
                    }];
                }
            
            } else {
                // Translate StackMob ID to Cache managed object ID and store
                NSManagedObject *setObject = [self.localManagedObjectContext objectWithID:[self SM_retrieveCacheObjectForRemoteID:[self referenceObjectForObjectID:propertyValueFromSerializedDict] entityName:[[property destinationEntity] name] createIfNeeded:YES]];
                
                NSString *objectToSetPrimaryKey = nil;
                if ([[[[property destinationEntity] name] lowercaseString] isEqualToString:[self.coreDataStore.session userSchema]]) {
                    objectToSetPrimaryKey = [self.coreDataStore.session userPrimaryKeyField];
                } else {
                    objectToSetPrimaryKey = [[property destinationEntity] primaryKeyField];
                }
                
                if (![setObject valueForKey:objectToSetPrimaryKey]) {
                    // Add a flag if this is a relationship reference
                    [setObject setValue:[NSString stringWithFormat:@"%@:nil", [self referenceObjectForObjectID:propertyValueFromSerializedDict]] forKey:[setObject primaryKeyField]];
                }
                [object setValue:setObject forKey:propertyName];
                
            }
        } else {
            [object setValue:nil forKey:propertyName];
        }
        
    }];
    
    NSError *saveError = nil;
    BOOL saveSuccess = [self SM_saveCache:&saveError];
    if (!saveSuccess) {
        if (SM_CORE_DATA_DEBUG) { DLog(@"Did Not Save Cache") }
    }
}

- (NSManagedObjectID *)SM_retrieveCacheObjectForRemoteID:(NSString *)remoteID entityName:(NSString *)entityName createIfNeeded:(BOOL)createIfNeeded {
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:entityName];
    NSEntityDescription *desc = [NSEntityDescription entityForName:entityName inManagedObjectContext:self.localManagedObjectContext];
    NSString *primaryKeyField = nil;
    if ([[entityName lowercaseString] isEqualToString:[self.coreDataStore.session userSchema]]) {
        primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
    } else {
        primaryKeyField = [desc primaryKeyField];
    }
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", primaryKeyField, remoteID];
    NSPredicate *nilReferencePredicate = [NSPredicate predicateWithFormat:@"%K == %@", primaryKeyField, [NSString stringWithFormat:@"%@:nil", remoteID]];
    NSArray *predicates = [NSArray arrayWithObjects:predicate, nilReferencePredicate, nil];
    NSPredicate *compoundPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
    [fetchRequest setPredicate:compoundPredicate];
    
    NSError *fetchError = nil;
    __block NSArray *results = [self.localManagedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
    if (fetchError || [results count] > 1) {
        // TODO handle error
    }
    
    
    __block NSManagedObject *cacheObject = nil;
    if ([results count] == 0 && createIfNeeded) {
        // Create new cache object
        cacheObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:self.localManagedObjectContext];
        NSError *permanentIdError = nil;
        [self.localManagedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObject:cacheObject] error:&permanentIdError];
        // Sanity check
        if (permanentIdError) {
            [NSException raise:SMExceptionCacheError format:@"Could not obtain permanent IDs for objects %@ with error %@", cacheObject, permanentIdError];
        }
        
        [self SM_insertRemoteID:remoteID withCacheObjectID:[cacheObject objectID] list:self.cacheMappingTable entityName:entityName];
        [self SM_saveCacheMap];
        if (SM_CORE_DATA_DEBUG) { DLog(@"Creating new cache object, %@", cacheObject) }
    } else {
        // result count == 1
        cacheObject = [results lastObject];
    }
    
    return cacheObject ? [cacheObject objectID] : nil;
    
    /*
    NSManagedObject *cacheObject = nil;
    NSString *cacheReferenceId = [self.cacheMappingTable objectForKey:remoteID];
    if (cacheReferenceId) {
        
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:entityName];
        NSEntityDescription *desc = [NSEntityDescription entityForName:entityName inManagedObjectContext:self.localManagedObjectContext];
        NSString *primaryKeyField;
        if ([[entityName lowercaseString] isEqualToString:[self.coreDataStore.session userSchema]]) {
            primaryKeyField = [self.coreDataStore.session userPrimaryKeyField];
        } else {
            primaryKeyField = [desc primaryKeyField];
        }
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", primaryKeyField, remoteID];
        [fetchRequest setPredicate:predicate];
        
        NSError *fetchError = nil;
        NSArray *results = [self.localManagedObjectContext executeFetchRequest:fetchRequest error:&fetchError];

        if (SM_CORE_DATA_DEBUG) {DLog(@"results are %@", results);}
        if ([results count] == 0) {
            // delete object we are replacing
            NSManagedObjectID *cacheObjectId = [[self localPersistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:cacheReferenceId]];
            NSManagedObject *objectToDelete = [self.localManagedObjectContext objectWithID:cacheObjectId];
            [self SM_purgeCacheManagedObjectFromCache:objectToDelete];
            // remove from cache map
            [self.cacheMappingTable removeObjectForKey:remoteID];
            
            // make new reference
            cacheObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:self.localManagedObjectContext];
            NSError *permanentIdError = nil;
            [self.localManagedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObject:cacheObject] error:&permanentIdError];
            // Sanity check
            if (permanentIdError) {
                [NSException raise:SMExceptionCacheError format:@"Could not obtain permanent IDs for objects %@ with error %@", cacheObject, permanentIdError];
            }
            
            [self SM_saveCacheMap];
            [self SM_insertStackMobID:remoteID inList:self.cacheMappingTable entityName:entityName];
            if (SM_CORE_DATA_DEBUG) { DLog(@"Creating new cache object, %@", cacheObject) }
        } else {
            return [[results objectAtIndex:0] objectID];
        }
    } else {
        cacheObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:self.localManagedObjectContext];
        NSError *permanentIdError = nil;
        [self.localManagedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObject:cacheObject] error:&permanentIdError];
        // Sanity check
        if (permanentIdError) {
            [NSException raise:SMExceptionCacheError format:@"Could not obtain permanent IDs for objects %@ with error %@", cacheObject, permanentIdError];
        }
        
        [self SM_saveCacheMap];
        [self SM_insertStackMobID:remoteID inList:self.cacheMappingTable entityName:entityName];
        if (SM_CORE_DATA_DEBUG) { DLog(@"Creating new cache object, %@", cacheObject) }
    }
    
    NSError *saveError = nil;
    BOOL saveSuccess = [self SM_saveCache:&saveError];
    if (!saveSuccess) {
        if (SM_CORE_DATA_DEBUG) { DLog(@"Did Not Save Cache") }
    }
    return [cacheObject objectID];
     */
}

- (void)SM_insertRemoteID:(NSString *)objectID withCacheObjectID:(NSManagedObjectID *)cacheObjectID list:(NSMutableDictionary *)list entityName:(NSString *)entityName
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    // TODO if remoteID already exists
    NSDictionary *tempDict = [list objectForKey:entityName];
    
    NSMutableDictionary *objectIDsForEntity = tempDict ? [tempDict mutableCopy] : [NSMutableDictionary dictionary];
    
    if ([[objectIDsForEntity allKeys] indexOfObject:objectID] == NSNotFound) {
        // TODO DLog
        NSLog(@"cacheObjectID is %@", cacheObjectID);
        NSString *cacheObjectIDString = [[cacheObjectID URIRepresentation] absoluteString];
        NSArray *components = [cacheObjectIDString componentsSeparatedByString:[NSString stringWithFormat:@"%@/", entityName]];
        NSString *valueToSave = [components lastObject];
        [objectIDsForEntity setObject:valueToSave forKey:objectID];
    } else {
        // Need to replace
        //[self.localManagedObjectContext]
        NSLog(@"got here");
    }
    
    [list setObject:[NSDictionary dictionaryWithDictionary:objectIDsForEntity] forKey:entityName];
}

- (BOOL)SM_isRemoteIDCached:(NSString *)objectID inList:(NSMutableDictionary *)list entityName:(NSString *)entityName
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    // TODO fix for dict structure
    NSArray *objectIDsForEntity = [list objectForKey:entityName];
    if (objectIDsForEntity && ([objectIDsForEntity indexOfObject:objectID] != NSNotFound) ) {
        return YES;
    }
    
    return NO;
}

- (void)SM_removeRemoteID:(NSString *)objectID inList:(NSMutableDictionary *)list entityName:(NSString *)entityName
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSDictionary *tempDict = [list objectForKey:entityName];
    
    NSMutableDictionary *objectIDsForEntity = tempDict ? [tempDict mutableCopy] : [NSMutableDictionary dictionary];
    
    if ([[objectIDsForEntity allKeys] indexOfObject:objectID] != NSNotFound) {
        [objectIDsForEntity removeObjectForKey:objectID];
    }
    
    // If count of objectIDsForEntity is now 0, remove entity name from list
    if ([objectIDsForEntity count] != 0) {
        [list setObject:[NSDictionary dictionaryWithDictionary:objectIDsForEntity] forKey:entityName];
    } else {
        [list removeObjectForKey:entityName];
    }
    
    
}

- (void)SM_addPrimaryKeysToDirtyQueueAndSave:(NSArray *)primaryKeys state:(int)state
{
    __block NSMutableArray *insertedList = [[self.dirtyQueue objectForKey:@"inserted"] mutableCopy];
    __block NSMutableArray *updatedList = [[self.dirtyQueue objectForKey:@"updated"] mutableCopy];
    __block NSMutableArray *deletedList = [[self.dirtyQueue objectForKey:@"deleted"] mutableCopy];
    switch (state) {
        case 0:
            [primaryKeys enumerateObjectsUsingBlock:^(id key, NSUInteger idx, BOOL *stop) {
                if (![insertedList containsObject:key]) {
                    [insertedList addObject:key];
                }
            }];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:insertedList] forKey:@"inserted"];
            break;
        case 1:
            // If an updated key already exists in inserted, leave it there
            [primaryKeys enumerateObjectsUsingBlock:^(id key, NSUInteger idx, BOOL *stop) {
                if (![insertedList containsObject:key] && ![updatedList containsObject:key]) {
                    [updatedList addObject:key];
                }
            }];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:insertedList] forKey:@"inserted"];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:updatedList] forKey:@"updated"];
            break;
        case 2:
            // If it exists in inserted, remove completely
            // If it exists in updated, move to deleted
            [primaryKeys enumerateObjectsUsingBlock:^(id key, NSUInteger idx, BOOL *stop) {
                if ([insertedList containsObject:key]) {
                    [insertedList removeObject:key];
                } else if ([updatedList containsObject:key]) {
                    [updatedList removeObject:key];
                    [deletedList addObject:key];
                } else if (![deletedList containsObject:key]) {
                    [deletedList addObject:key];
                }
            }];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:insertedList] forKey:@"inserted"];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:updatedList] forKey:@"updated"];
            [self.dirtyQueue setObject:[NSArray arrayWithArray:deletedList] forKey:@"deleted"];
            break;
        default:
            [NSException raise:SMExceptionIncompatibleObject format:@"State %d not recognized", state];
            break;
    }
    
    [self SM_saveDirtyQueue];
}

- (BOOL)SM_saveCache:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    // Save Cache if has changes
    if ([self.localManagedObjectContext hasChanges]) {
        __block BOOL localCacheSaveSuccess;
        [self.localManagedObjectContext performBlockAndWait:^{
            localCacheSaveSuccess = [self.localManagedObjectContext save:error];
        }];
        if (!localCacheSaveSuccess) {
            if (NULL != error) {
                *error = (__bridge id)(__bridge_retained CFTypeRef)*error;
            }
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - Purging the Cache

- (void)SM_didRecievePurgeObjectFromCacheNotification:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSDictionary *notificationUserInfo = [notification userInfo];
    NSManagedObjectID *objectID = [notificationUserInfo objectForKey:SMCachePurgeManagedObjectID];
    
    if ([[objectID persistentStore] class] == [SMIncrementalStore class]) {
        NSString *objectIDReference = [(SMIncrementalStore *)[objectID persistentStore] referenceObjectForObjectID:objectID];
        NSError *purgeError = nil;
        NSDictionary *objectInfo = [NSDictionary dictionaryWithObjectsAndKeys:objectIDReference, ObjectID, [[objectID entity] name], ObjectEntityName, nil];
        [self SM_purgeObjectFromCacheWithStackMobIDInfo:objectInfo error:&purgeError];
    }
}

- (void)SM_didRecievePurgeObjectsFromCacheNotification:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSDictionary *notificationUserInfo = [notification userInfo];
    NSArray *objectIDsToPurge = [notificationUserInfo objectForKey:SMCachePurgeArrayOfManageObjectIDs];
    
    NSMutableArray *objectsInfo = [NSMutableArray arrayWithCapacity:[objectIDsToPurge count]];
    [objectIDsToPurge enumerateObjectsUsingBlock:^(id objectID, NSUInteger idx, BOOL *stop) {
        
        if([[objectID persistentStore] class] == [SMIncrementalStore class]) {
            NSString *objectIDReference = [(SMIncrementalStore *)[objectID persistentStore] referenceObjectForObjectID:objectID];
            // Get
            NSDictionary *objectInfo = [NSDictionary dictionaryWithObjectsAndKeys:objectIDReference, ObjectID, [[objectID entity] name], ObjectEntityName, nil];
            [objectsInfo addObject:objectInfo];
        }
    }];
    
    [self SM_purgeObjectsFromCacheByStackMobIDInfo:objectsInfo];
    
    
}

- (void)SM_didRecievePurgeObjectFromCacheByEntityNotification:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSString *entityName = [[notification userInfo] objectForKey:SMCachePurgeOfObjectsFromEntityName];
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:entityName];
    NSError *error = nil;
    NSArray *results = [self.localManagedObjectContext executeFetchRequest:request error:&error];
    if (!error) {
        [self SM_purgeCacheManagedObjectsFromCache:results];
    }
}

- (void)SM_didRecieveCacheResetNotification:(NSNotification *)notification
{
    if (SM_CORE_DATA_DEBUG) { DLog() }
    NSURL *storeURL = [self SM_getStoreURLForFileComponent:SQL_DB];
    [self SM_removeStoreURLPath:storeURL];
    
    [self.cacheMappingTable removeAllObjects];
    [self SM_saveCacheMap];
    
    _localManagedObjectContext = nil;
    _localPersistentStoreCoordinator = nil;
    _localManagedObjectModel = nil;
    _localManagedObjectContext = self.localManagedObjectContext;
}

- (BOOL)SM_purgeCacheManagedObjectsFromCache:(NSArray *)arrayOfManagedObjects
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block BOOL success = YES;
    
    NSMutableArray *arrayOfManagedObjectInfo = [NSMutableArray arrayWithCapacity:[arrayOfManagedObjects count]];
    
    [arrayOfManagedObjects enumerateObjectsUsingBlock:^(id object, NSUInteger idx, BOOL *stop) {
        NSString *objectID = [object valueForKey:[object primaryKeyField]];
        NSArray *array = [objectID componentsSeparatedByString:@":"];
        objectID = [array count] > 1 ? [array objectAtIndex:0] : objectID;
        NSDictionary *objectInfo = [NSDictionary dictionaryWithObjectsAndKeys:[[object entity] name], ObjectEntityName, objectID, ObjectID, nil];
        [arrayOfManagedObjectInfo addObject:objectInfo];
        [self.localManagedObjectContext deleteObject:object];
    }];
    
    if ([self.localManagedObjectContext hasChanges]) {
        
        NSError *anError = nil;
        success = [self SM_saveCache:&anError];
        
        if (success) {
            [arrayOfManagedObjectInfo enumerateObjectsUsingBlock:^(id objectInfo, NSUInteger idx, BOOL *stop) {
                
                [self SM_removeRemoteID:[objectInfo objectForKey:ObjectID] inList:self.cacheMappingTable entityName:[objectInfo objectForKey:ObjectEntityName]];
                
                /*
                NSString *stringRepOfRelationshipCacheID = [[[object objectID] URIRepresentation] absoluteString];
                
                NSArray *matchingKeys = [self.cacheMappingTable allKeysForObject:stringRepOfRelationshipCacheID];
                
                if ([matchingKeys count] == 1) {
                    [self.cacheMappingTable removeObjectForKey:[matchingKeys lastObject]];
                } else if ([matchingKeys count] > 1) {
                    // This means the object was never placed in the cache map, or duplicated
                    [NSException raise:SMExceptionCacheError format:@"Key for cache object ID found incorrect number of times.  Matching keys for ID: %ld", (unsigned long)[matchingKeys count]];
                }
                 */
            }];
            [self SM_saveCacheMap];
        } else {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Error saving cache: %@", anError) }
        }
        
    }
    
    
    return success;
}

- (BOOL)SM_purgeCacheManagedObjectFromCache:(NSManagedObject *)object
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    BOOL success = YES;
    NSString *objectID = [object valueForKey:[object primaryKeyField]];
    NSArray *array = [objectID componentsSeparatedByString:@":"];
    objectID = [array count] > 1 ? [array objectAtIndex:0] : objectID;
    NSDictionary *objectInfo = [NSDictionary dictionaryWithObjectsAndKeys:[[object entity] name], ObjectEntityName, objectID, ObjectID, nil];
    [self.localManagedObjectContext deleteObject:object];
    NSError *anError = nil;
    success = [self SM_saveCache:&anError];
    
    // Remove the entry from map table
    if (success) {
        // Convert ID to string rep, get StackMob ID key and delete
        [self SM_removeRemoteID:[objectInfo objectForKey:ObjectID] inList:self.cacheMappingTable entityName:[objectInfo objectForKey:ObjectEntityName]];
        /*
        NSString *stringRepOfRelationshipCacheID = [[[object objectID] URIRepresentation] absoluteString];
        
        NSArray *matchingKeys = [self.cacheMappingTable allKeysForObject:stringRepOfRelationshipCacheID];
        
        if ([matchingKeys count] == 1) {
            [self.cacheMappingTable removeObjectForKey:[matchingKeys lastObject]];
        } else if ([matchingKeys count] > 1) {
            // This means the object was never placed in the cache map, or duplicated
            [NSException raise:SMExceptionCacheError format:@"Key for cache object ID found incorrect number of times.  Matching keys for ID: %ld", (unsigned long)[matchingKeys count]];
        }
        [self.cacheMappingTable removeObjectForKey:[matchingKeys lastObject]];
         */
        [self SM_saveCacheMap];
    } else {
        if (SM_CORE_DATA_DEBUG) { DLog(@"Error saving cache: %@", anError) }
    }
    
    return success;
}

- (BOOL)SM_purgeObjectsFromCacheByStackMobIDInfo:(NSArray *)arrayOfStackMobObjectIDInfo
{
    // TODO update this
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block BOOL success = YES;
    
    [arrayOfStackMobObjectIDInfo enumerateObjectsUsingBlock:^(id objectInfo, NSUInteger idx, BOOL *stop) {
        NSManagedObjectID *cacheObjectID = [self SM_retrieveCacheObjectForRemoteID:[objectInfo objectForKey:ObjectID] entityName:[objectInfo objectForKey:ObjectEntityName] createIfNeeded:NO];
        
        if (cacheObjectID) {
            NSError *anError = nil;
            NSManagedObject *cacheObject = [self.localManagedObjectContext existingObjectWithID:cacheObjectID error:&anError];
            if (anError) {
                DLog(@"Did not get cache object with error %@", anError)
                success = NO;
                *stop = YES;
                
            } else {
                // delete object from cache
                [self.localManagedObjectContext deleteObject:cacheObject];
            }
        }
    }];
    
    if (success && [self.localManagedObjectContext hasChanges]) {
        NSError *anError = nil;
        success = [self SM_saveCache:&anError];
        
        // Remove the entry from map table
        if (success) {
            [arrayOfStackMobObjectIDInfo enumerateObjectsUsingBlock:^(id objectInfo, NSUInteger idx, BOOL *stop) {
                [self SM_removeRemoteID:[objectInfo objectForKey:ObjectID] inList:self.cacheMappingTable entityName:[objectInfo objectForKey:ObjectEntityName]];
            }];
            [self SM_saveCacheMap];
        } else {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Error saving cache: %@", anError) }
        }
    }
    
    return success;
}

- (BOOL)SM_purgeObjectFromCacheWithStackMobIDInfo:(NSDictionary *)objectInfo error:(NSError *__autoreleasing*)error
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    BOOL success = YES;
    
    NSManagedObjectID *cacheObjectID = [self SM_retrieveCacheObjectForRemoteID:[objectInfo objectForKey:ObjectID] entityName:[objectInfo objectForKey:ObjectEntityName] createIfNeeded:NO];
    NSError *anError = nil;
    NSManagedObject *cacheObject = [self.localManagedObjectContext existingObjectWithID:cacheObjectID error:&anError];
    if (anError) {
        if (SM_CORE_DATA_DEBUG) { DLog(@"Did not get cache object with error %@", anError) }
        success = NO;
        if (error != NULL) {
            *error = (__bridge id)(__bridge_retained CFTypeRef)anError;
        }
    } else {
        // Purge the cache
        [self.localManagedObjectContext deleteObject:cacheObject];
        
        success = [self SM_saveCache:&anError];
        
        // Remove the entry from map table
        if (success) {
            [self SM_removeRemoteID:[objectInfo objectForKey:ObjectID] inList:self.cacheMappingTable entityName:[objectInfo objectForKey:ObjectEntityName]];
            [self SM_saveCacheMap];
        } else {
            if (SM_CORE_DATA_DEBUG) { DLog(@"Error saving cache: %@", anError) }
            if (error != NULL) {
                *error = (__bridge id)(__bridge_retained CFTypeRef)anError;
            }
        }
    }
    
    return success;
}


////////////////////////////
#pragma mark - Misc Internal Methods
////////////////////////////

- (NSString *)SM_remoteKeyForEntityName:(NSString *)entityName {
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    return [[entityName lowercaseString] stringByAppendingString:@"_id"];
}

/*
 Returns a dictionary that has extra fields from StackMob that aren't present as attributes or relationships in the Core Data representation stripped out.  Examples may be StackMob added createddate or lastmoddate.
 */
- (NSDictionary *)SM_responseSerializationForDictionary:(NSDictionary *)theObject schemaEntityDescription:(NSEntityDescription *)entityDescription managedObjectContext:(NSManagedObjectContext *)context includeRelationships:(BOOL)includeRelationships
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    __block NSMutableDictionary *serializedDictionary = [NSMutableDictionary dictionary];
    
    [entityDescription.attributesByName enumerateKeysAndObjectsUsingBlock:^(id attributeName, id attributeValue, BOOL *stop) {
        NSAttributeDescription *attributeDescription = (NSAttributeDescription *)attributeValue;
        if (attributeDescription.attributeType != NSUndefinedAttributeType) {
            if ([[theObject allKeys] indexOfObject:[entityDescription SMFieldNameForProperty:attributeDescription]] != NSNotFound) {
                id value = [theObject valueForKey:[entityDescription SMFieldNameForProperty:attributeDescription]];
                if (value == [NSNull null]) {
                    [serializedDictionary setObject:value forKey:attributeName];
                } else if (value && attributeDescription.attributeType == NSDateAttributeType) {
                    unsigned long long convertedValue = [value unsignedLongLongValue] / 1000;
                    NSDate *convertedDate = [NSDate dateWithTimeIntervalSince1970:convertedValue];
                    [serializedDictionary setObject:convertedDate forKey:attributeName];
                } else if (value && attributeDescription.attributeType == NSTransformableAttributeType) {
                    if ([value isKindOfClass:[NSDictionary class]]) {
                        // we know it's a geopoint dictionary
                        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:value];
                        [serializedDictionary setObject:data forKey:attributeName];
                    }
                } else {
                    [serializedDictionary setObject:value forKey:attributeName];
                }
            }
        }
    }];
    
    [entityDescription.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(id relationshipName, id relationshipValue, BOOL *stop) {
        NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)relationshipValue;
        // get the relationship contents for the property
        id relationshipContents = [theObject valueForKey:[entityDescription SMFieldNameForProperty:relationshipDescription]];
        if (![relationshipDescription isToMany]) {
            if (relationshipContents && relationshipContents != [NSNull null]) {
                NSEntityDescription *entityDescriptionForRelationship = [NSEntityDescription entityForName:[[relationshipValue destinationEntity] name] inManagedObjectContext:context];
                if ([relationshipContents isKindOfClass:[NSString class]]) {
                    NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:entityDescriptionForRelationship referenceObject:relationshipContents];
                    [serializedDictionary setObject:relationshipObjectID forKey:relationshipName];
                }
            } else {
                [serializedDictionary setObject:[NSNull null] forKey:relationshipName];
            }
        } else if (relationshipContents && includeRelationships) {
            // to many relationship
            if (![relationshipContents isKindOfClass:[NSArray class]]) {
                [NSException raise:SMExceptionIncompatibleObject format:@"Relationship contents should be an array for a to-many relationship. The relationship passed has contents that are of class type %@. Confirm that this relationship was meant to be to-many.", [relationshipContents class]];
            }
            NSMutableArray *relatedObjects = [NSMutableArray array];
            [(NSSet *)relationshipContents enumerateObjectsUsingBlock:^(id stringIdReference, BOOL *stopEnumOfRelatedObjects) {
                NSManagedObjectID *relationshipObjectID = [self newObjectIDForEntity:[relationshipDescription destinationEntity] referenceObject:stringIdReference];
                [relatedObjects addObject:relationshipObjectID];
            }];
            [serializedDictionary setObject:[NSSet setWithArray:relatedObjects] forKey:relationshipName];
        }
    }];
    
    if (SM_CORE_DATA_DEBUG) {
        DLog(@"read object from server is %@", theObject)
        DLog(@"serialized dictionary to return is %@", serializedDictionary)
    }
    
    return [NSDictionary dictionaryWithDictionary:serializedDictionary];
}

- (BOOL)SM_addPasswordToSerializedDictionary:(NSDictionary **)originalDictionary originalObject:(SMUserManagedObject *)object
{
    if (SM_CORE_DATA_DEBUG) {DLog()}
    
    NSMutableDictionary *dictionaryToReturn = [*originalDictionary mutableCopy];
    
    NSMutableDictionary *serializedDictCopy = [[*originalDictionary objectForKey:SerializedDictKey] mutableCopy];
    
    NSString *passwordIdentifier = [self.coreDataStore.session.userIdentifierMap objectForKey:[object valueForKey:[object primaryKeyField]]];
    
    if (!passwordIdentifier) {
        [NSException raise:SMExceptionIncompatibleObject format:@"No password identifier found for object.  This might be happening if you are using two instances of SMClient.  If you are unable to resolve yourself, please submit a support ticket to StackMob."];
    }
    
    NSString *thePassword = [KeychainWrapper keychainStringFromMatchingIdentifier:passwordIdentifier];
    
    if (!thePassword) {
        return NO;
    }
    
    [serializedDictCopy setObject:thePassword forKey:[[[self coreDataStore] session] userPasswordField]];
    
    [dictionaryToReturn setObject:serializedDictCopy forKey:SerializedDictKey];
    
    *originalDictionary = dictionaryToReturn;
    
    return YES;
}

@end
