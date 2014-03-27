/*
** ADOBE SYSTEMS INCORPORATED
** Copyright 2012 Adobe Systems Incorporated
** All Rights Reserved.
**
** NOTICE:  Adobe permits you to use, modify, and distribute this file in accordance with the
** terms of the Adobe license agreement accompanying it.  If you have received this file from a
** source other than Adobe, then your use, modification, or distribution of it requires the prior
** written permission of Adobe.
*/
#include <stdio.h>
#include <pthread.h>
#include "AS3/AS3.h"

static char threadBuf[256];

static void *threadProc(void *arg)
{
  static int counter = 0;
  printf("Thread proc!\n");
  sprintf(threadBuf, "threadProc invoked %d times", ++counter);
  return NULL;
}

static pthread_t thread;

void spawnThread() __attribute__((used, annotate("as3sig:public function spawnThread():void")));

void spawnThread()
{
  printf("spawnThread run\n");
  pthread_create(&thread, NULL, threadProc, NULL);
  pthread_join(thread, NULL);
  printf("spawnThread joined (%s)\n", threadBuf);
}

int main()
{
  printf("main run\n");
  pthread_create(&thread, NULL, threadProc, NULL);
  pthread_join(thread, NULL);
  printf("main joined (%s)\n", threadBuf);

  AS3_GoAsync();
}
