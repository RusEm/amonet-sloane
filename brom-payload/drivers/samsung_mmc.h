#pragma once

#define FW_ADDR 0x40000
#define BLOCK_SIZE 512

int mmc_enter_read_ram(struct msdc_host *host);
int mmc_exit_cmd62(struct msdc_host *host);
int dump_fw(struct msdc_host *host, int size, void *buf);