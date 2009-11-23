#ifndef __VSCAN_SOPHOS_H_
#define __VSCAN_SOPHOS_H_

#include "vscan-global.h"


/* Configuration Section :-) */

/* Sophie stuff: 
   socket name of Sophie daemon */
#define SOPHIE_SOCKET_NAME      "/var/run/sophie"

/* default location of samba-style configuration file (needs Samba >= 2.2.4
 or Samba 3.0 */

#define PARAMCONF "/etc/samba/vscan-sophos.conf"


/* False = log only infected file, True = log every file access */

#ifndef VSCAN_VERBOSE_FILE_LOGGING
# define VSCAN_VERBOSE_FILE_LOGGING False   
#endif

/* if a file is bigger than VSCAN_MAX_SIZE it won't be scanned. Has to be
   specified in bytes! If it set to 0, the file size check is disabled */

#ifndef VSCAN_MAX_SIZE 
# define VSCAN_MAX_SIZE 0 
#endif

/* True = scan files on open */

#ifndef VSCAN_SCAN_ON_OPEN 
# define VSCAN_SCAN_ON_OPEN True 
#endif

/* True = scan files on close */

#ifndef VSCAN_SCAN_ON_CLOSE
# define VSCAN_SCAN_ON_CLOSE False
#endif

/* True = deny access in case of virus scanning failure */

#ifndef VSCAN_DENY_ACCESS_ON_ERROR
# define VSCAN_DENY_ACCESS_ON_ERROR True
#endif

/* True = deny access in case of minor virus scanning failure */

#ifndef VSCAN_DENY_ACCESS_ON_MINOR_ERROR
# define VSCAN_DENY_ACCESS_ON_MINOR_ERROR True
#endif

/* True = send a warning message via window messenger service for viruses found */

#ifndef VSCAN_SEND_WARNING_MESSAGE
# define VSCAN_SEND_WARNING_MESSAGE True
#endif

/* default infected file action */
#define VSCAN_INFECTED_FILE_ACTION INFECTED_QUARANTINE

/* default quarantine settings; hopefully the user changes this */
#define VSCAN_QUARANTINE_DIRECTORY "/tmp"
#define VSCAN_QUARANTINE_PREFIX    "vir-"

/* set default value for maximum lrufile entries */
#define VSCAN_MAX_LRUFILES 100

/* time after an entry is considered as expired */
#define VSCAN_LRUFILES_INVALIDATE_TIME 5


/* End Configuration Section */

/* functions by vscan-sophos_core */
/* opens socket */
int vscan_sophos_init(void); 
/* scans a file */
int vscan_sophos_scanfile(int sockfd, char *scan_file, char *client_ip);
/* terminates SAVI */
void vscan_sophos_end(int sockfd);


#endif /* __VSCAN_SOPHOS_H_ */
