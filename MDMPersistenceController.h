//
//  MDMPersistenceController.h
//
//  Created by Matthew Morey on 11/19/13.
//  Copyright (c) 2013 Matthew Morey. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const MDMPersistenceControllerDidInitialize;

@interface MDMPersistenceController : NSObject

/**
 The persistence controller's main managed object context. (read-only)
 */
@property (nonatomic, strong, readonly) NSManagedObjectContext *managedObjectContext;

/**
 Returns a persistence controller initialized with the given arguments.
 
 @param storeURL The URL of the SQLite store to load.
 @param model A managed object model.

 @return A new persistence controller object with a store at the specified location with model.
 */
- (id)initWithStoreURL:(NSURL *)storeURL model:(NSManagedObjectModel *)model;

/**
 Returns a persistence controller initialized with the given arguments.
 
 @param storeURL The URL of the SQLite store to load.
 @param modelURL The URL of the managed object model.

 @return A new persistence controller object with a store at the specified location and a model at the specified location.
 */
- (id)initWithStoreURL:(NSURL *)storeURL modelURL:(NSURL *)modelURL;

/**
 Returns a new private child managed object context with a concurrency type of `NSPrivateQueueConcurrencyType` and a parent context of `self.managedObjectContext`.
 
 @return A new managed object context object.
 */
- (NSManagedObjectContext *)newPrivateChildManagedObjectContext;

/**
 Returns a new child managed object context with a concurrency type of `NSMainQueueConcurrencyType` and a parent context of `self.managedObjectContext`.
 
 @return A new managed object context object.
 */
- (NSManagedObjectContext *)newChildManagedObjectContext;

/**
 Attempts to commit unsaved changes to registered objects to disk.
 
 @param wait If set the primary context is saved synchronously otherwise asynchronously.
 */
- (void)saveContextAndWait:(BOOL)wait;
    
@end
