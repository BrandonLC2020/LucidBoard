from django.http import JsonResponse
from django.urls import path

from api.ninja import api

urlpatterns = [
    path("", api.urls),
]


def handler404(request, exception):
    return JsonResponse({"detail": "Not found", "code": "not_found"}, status=404)
