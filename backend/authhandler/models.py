from django.db import models

# Create your models here.
class Device(models.Model):
    id = models.AutoField(primary_key=True)
    device_code = models.CharField(max_length=255, unique=True)
    device_name = models.CharField(max_length=255,null=True, blank=True)
    device_ip = models.GenericIPAddressField(null=True, blank=True)
    user_code = models.CharField(max_length=255, unique=True)
    verification_uri = models.CharField(max_length=255)

    def __str__(self):
        return f"{self.device_name} ({self.device_code})"