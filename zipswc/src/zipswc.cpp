#include <stdio.h>
#include "AS3/AS3.h"

void testme() __attribute__((used,
		annotate("as3sig:public function testme(zipfile:ByteArray, output:ByteArray):void"),
		annotate("as3import:flash.utils.ByteArray")
	));

// http://stackoverflow.com/questions/14326828/how-to-pass-bytearray-to-c-code-using-flascc

void testme()
{
  printf("testme() called!\n");

  char *byteArray_c;
  unsigned int len;

  inline_as3("%0 = byteData.bytesAvailable;" : "=r"(len));
  byteArray_c = (char *)malloc(len);

  inline_as3("CModule.ram.position = %0;" : : "r"(byteArray_c));
  inline_as3("byteData.readBytes(CModule.ram);");

  // Now byteArray_c points to a copy of the data from byteData.
  // Note that byteData.position has changed to the end of the stream.

  // ... do stuff ...

  free(byteArray_c);

}

int main()
{
  printf("main() called\n");

  AS3_GoAsync();
}
