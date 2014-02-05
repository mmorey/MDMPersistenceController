//
//  MDMPersistenceController.m
//
//  Created by Matthew Morey on 11/19/13.
//  Copyright (c) 2013 Matthew Morey. All rights reserved.
//

#import "MRPersistenceController.h"
#import <CoreData/CoreData.h>
#import "MDMFatalErrorAlertView.h"
#import "NSNotificationCenter+MDMAdditions.h"

NSString *const MDMPersistenceControllerDidInitialize = @"MDMPersistenceControllerDidInitialize";

@interface MDMPersistenceController () <UIAlertViewDelegate>

@property (nonatomic, strong, readwrite) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSManagedObjectContext *writerObjectContext;
@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSManagedObjectModel *model;

@end

@implementation MRPersistenceController

- (id)initWithStoreURL:(NSURL *)storeURL model:(NSManagedObjectModel *)model {
    
    self = [super init];
    if (self) {
        _storeURL = storeURL;
        _model = model;
        if ([self setupPersistenceStack] == NO) {
            return nil;
        }
    }
    
    return self;
}

- (id)initWithStoreURL:(NSURL *)storeURL modelURL:(NSURL *)modelURL {
    
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    ZAssert(model, @"ERROR: NSManagedObjectModel is nil");
    
    return [self initWithStoreURL:storeURL model:model];
}

- (BOOL)setupPersistenceStack {
    
    // Create persistent store coordinator
    NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    ZAssert(persistentStoreCoordinator, @"ERROR: NSPersistentStoreCoordinator is nil");
    
    // Add persistent store to store coordinator
    NSDictionary *persistentStoreOptions = @{ // Light migration
                                             NSInferMappingModelAutomaticallyOption:@YES,
                                             NSMigratePersistentStoresAutomaticallyOption:@YES
                                             };
    NSError *persistentStoreError;
    NSPersistentStore *persistentStore = [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                                  configuration:nil
                                                                                            URL:self.storeURL
                                                                                        options:persistentStoreOptions
                                                                                          error:&persistentStoreError];
    if (persistentStore == nil) {
        
        // Model has probably changed, lets delete the old one and try again
        NSError *removeSQLiteFilesError = nil;
        if ([self removeSQLiteFilesAtStoreURL:self.storeURL error:&removeSQLiteFilesError]) {
            
            persistentStoreError = nil;
            persistentStore = [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                       configuration:nil
                                                                                 URL:self.storeURL
                                                                             options:persistentStoreOptions
                                                                               error:&persistentStoreError];
        } else {
            
            ALog(@"ERROR: Could not remove SQLite files\n%@", [removeSQLiteFilesError localizedDescription]);
            
            return NO;
        }
        
        if (persistentStore == nil) {
            
            // Something really bad is happening
            ALog(@"ERROR: NSPersistentStore is nil: %@\n%@", [persistentStoreError localizedDescription], [persistentStoreError userInfo]);
            
            return NO;
        }
    }
    
    // Create managed object contexts
    self.writerObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.writerObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
    if (self.writerObjectContext == nil) {
        
        // App is useless if a writer managed object context cannot be created
        ALog(@"ERROR: NSManagedObjectContext is nil");
        
        return NO;
    }
    
    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [self.managedObjectContext setParentContext:self.writerObjectContext];
    if (self.managedObjectContext == nil) {
        
        // App is useless if a managed object context cannot be created
        ALog(@"ERROR: NSManagedObjectContext is nil");
        
        return NO;
    }
    
    // Context is fully initialized, notify view controllers
    [self persistenceStackInitialized];
    
    return YES;
}

- (BOOL)removeSQLiteFilesAtStoreURL:(NSURL *)storeURL error:(NSError * __autoreleasing *)error {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *storeDirectory = [storeURL URLByDeletingLastPathComponent];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:storeDirectory
                                          includingPropertiesForKeys:nil
                                                             options:0
                                                        errorHandler:nil];
    
    NSString *storeName = [storeURL.lastPathComponent stringByDeletingPathExtension];
    for (NSURL *url in enumerator) {
        
        if ([url.lastPathComponent hasPrefix:storeName] == NO) {
            continue;
        }
        
        NSError *fileManagerError = nil;
        if ([fileManager removeItemAtURL:url error:&fileManagerError] == NO) {
           
            if (error != NULL) {
                *error = fileManagerError;
            }
            
            return NO;
        }
    }
    
    return YES;
}

- (void)persistenceStackInitialized {
    
    [[NSNotificationCenter defaultCenter] MDMPostNotificationNameOnMainThread:MDMPersistenceControllerDidInitialize object:self];
}

- (void)saveContextAndWait:(BOOL)wait {
    
    if (self.managedObjectContext == nil) {
        return;
    }
    
    if ([self.managedObjectContext hasChanges] || [self.writerObjectContext hasChanges]) {
        
        [self.managedObjectContext performBlockAndWait:^{
            
            NSError *mainContextSaveError = nil;
            if ([self.managedObjectContext save:&mainContextSaveError] == NO) {
                
                ALog(@"ERROR: Could not save managed object context -  %@\n%@", [mainContextSaveError localizedDescription], [mainContextSaveError userInfo]);
                [self showFatalErrorAlert];
            }
            
            if ([self.writerObjectContext hasChanges]) {
               
                if (wait) {
                    [self.writerObjectContext performBlockAndWait:[self savePrivateWriterContextBlock]];
                } else {
                    [self.writerObjectContext performBlock:[self savePrivateWriterContextBlock]];
                }
            }
        }]; // Managed Object Context block
    } // Managed Object Context has changes
}

- (void(^)())savePrivateWriterContextBlock {
    
    void (^savePrivate)(void) = ^{
        
        NSError *privateContextError = nil;
        if ([self.writerObjectContext save:&privateContextError] == NO) {
            
            ALog(@"ERROR: Could not save managed object context - %@\n%@", [privateContextError localizedDescription], [privateContextError userInfo]);
            [self showFatalErrorAlert];
        }
    };
    
    return savePrivate;
}

#pragma mark - Fatal Error Alert

//
// A save error should never happen in production. The asserts in the
//   saveContext method will catch developer issues, which is the
//   problem 99.9% of the time. If the app does crash in production
//   the abort() will generate a stack trace that can hopefully be
//   used to track down the issue.
//
- (void)showFatalErrorAlert {

    MRFatalErrorAlertView *alertView = [[MRFatalErrorAlertView alloc] init];
    [alertView showAlert];
}

#pragma mark - Child NSManagedObjectContext

- (NSManagedObjectContext *)newPrivateChildManagedObjectContext {
    
    NSManagedObjectContext *privateChildManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [privateChildManagedObjectContext setParentContext:self.managedObjectContext];
    
    return privateChildManagedObjectContext;
}

- (NSManagedObjectContext *)newChildManagedObjectContext {
    
    NSManagedObjectContext *childManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [childManagedObjectContext setParentContext:self.managedObjectContext];
    
    return childManagedObjectContext;
}

@end
